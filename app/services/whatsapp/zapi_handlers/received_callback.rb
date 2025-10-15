module Whatsapp::ZapiHandlers::ReceivedCallback # rubocop:disable Metrics/ModuleLength
  include Whatsapp::ZapiHandlers::Helpers

  private

  def process_received_callback
    @raw_message = processed_params
    @message = nil
    @contact_inbox = nil
    @contact = nil

    return unless should_process_message?
    return if find_message_by_source_id(raw_message_id) || message_under_process?

    cache_message_source_id_in_redis

    return handle_edited_message if @raw_message[:isEdit]

    set_contact

    unless @contact
      Rails.logger.warn "Contact not found for message: #{raw_message_id}"
      return
    end

    set_conversation
    handle_create_message
  ensure
    clear_message_source_id_from_redis
  end

  def should_process_message?
    !@raw_message[:isGroup] &&
      !@raw_message[:isNewsletter] &&
      !@raw_message[:broadcast] &&
      !@raw_message[:isStatusReply]
  end

  def message_type # rubocop:disable Metrics/CyclomaticComplexity
    return 'reaction' if @raw_message.key?(:reaction)
    return 'text' if @raw_message.key?(:text)
    return 'image' if @raw_message.key?(:image)
    return 'sticker' if @raw_message.key?(:sticker)
    return 'audio' if @raw_message.key?(:audio)
    return 'video' if @raw_message.key?(:video)
    return 'file' if @raw_message.key?(:document)

    'unsupported'
  end

  def message_content
    case message_type
    when 'text'
      @raw_message.dig(:text, :message)
    when 'image'
      @raw_message.dig(:image, :caption)
    when 'video'
      @raw_message.dig(:video, :caption)
    when 'file'
      @raw_message.dig(:document, :fileName)
    when 'reaction'
      @raw_message.dig(:reaction, :value)
    end
  end

  def contact_name
    @raw_message[:chatName] || @raw_message[:senderName] || @raw_message[:phone]
  end

  def set_contact
    push_name = contact_name
    source_id = @raw_message[:phone]

    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: source_id,
      inbox: inbox,
      contact_attributes: { name: push_name, phone_number: "+#{source_id}" }
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact

    @contact.update!(name: push_name) if @contact.name == source_id
    try_update_contact_avatar
  end

  def try_update_contact_avatar
    avatar_url = @raw_message[:senderPhoto] || @raw_message[:photo]
    return unless avatar_url.present? && avatar_url.start_with?('http')

    Avatar::AvatarFromUrlJob.perform_later(@contact, avatar_url)
  end

  def handle_create_message
    create_message(attach_media: %w[image sticker file video audio].include?(message_type))
  end

  def create_message(attach_media: false)
    @message = @conversation.messages.build(
      content: message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      source_id: raw_message_id,
      sender: incoming_message? ? @contact : @inbox.account.account_users.first.user,
      sender_type: incoming_message? ? 'Contact' : 'User',
      message_type: incoming_message? ? :incoming : :outgoing,
      content_attributes: message_content_attributes
    )

    handle_attach_media if attach_media

    @message.save!

    inbox.channel.received_messages([@message], @conversation) if incoming_message?
  end

  def message_content_attributes
    type = message_type
    content_attributes = { external_created_at: @raw_message[:momment] / 1000 }

    if type == 'reaction'
      content_attributes[:in_reply_to_external_id] = @raw_message.dig(:reaction, :referencedMessage, :messageId)
      content_attributes[:is_reaction] = true
    elsif type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    content_attributes[:in_reply_to_external_id] = @raw_message[:referenceMessageId] if @raw_message[:referenceMessageId].present?

    content_attributes
  end

  def handle_attach_media
    attachment_file = download_attachment_file

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: { io: attachment_file, filename: filename, content_type: message_mimetype }
    )

    attachment.meta = { is_recorded_audio: true } if @raw_message.dig(:audio, :ptt)
  rescue Down::Error => e
    @message.update!(is_unsupported: true)
    Rails.logger.error "Failed to download attachment for message #{raw_message_id}: #{e.message}"
  end

  def download_attachment_file
    media_url = case message_type
                when 'image'
                  @raw_message.dig(:image, :imageUrl)
                when 'sticker'
                  @raw_message.dig(:sticker, :stickerUrl)
                when 'audio'
                  @raw_message.dig(:audio, :audioUrl)
                when 'video'
                  @raw_message.dig(:video, :videoUrl)
                when 'file'
                  @raw_message.dig(:document, :documentUrl)
                end

    Down.download(media_url)
  end

  def filename
    case message_type
    when 'file'
      @raw_message.dig(:document, :fileName)
    else
      ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
      "#{file_content_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
    end
  end

  def file_content_type
    return :image if %w[image sticker].include?(message_type)
    return :video if message_type == 'video'
    return :audio if message_type == 'audio'

    :file
  end

  def message_mimetype
    case message_type
    when 'image'
      @raw_message.dig(:image, :mimeType)
    when 'sticker'
      @raw_message.dig(:sticker, :mimeType)
    when 'video'
      @raw_message.dig(:video, :mimeType)
    when 'audio'
      @raw_message.dig(:audio, :mimeType)
    when 'file'
      @raw_message.dig(:document, :mimeType)
    end
  end

  def handle_edited_message
    @message = find_message_by_source_id(@raw_message[:messageId])
    return unless @message

    @message.update!(
      content: message_content,
      is_edited: true,
      previous_content: @message.content
    )
  end
end
