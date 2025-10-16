module Whatsapp::BaileysHandlers::Helpers # rubocop:disable Metrics/ModuleLength
  include Whatsapp::IncomingMessageServiceHelpers

  private

  def raw_message_id
    @raw_message[:key][:id]
  end

  def incoming?
    !@raw_message[:key][:fromMe]
  end

  def jid_type # rubocop:disable Metrics/CyclomaticComplexity
    jid = @raw_message[:key][:remoteJid]
    server = jid.split('@').last

    # NOTE: Based on Baileys internal functions
    # https://github.com/WhiskeySockets/Baileys/blob/v6.7.16/src/WABinary/jid-utils.ts#L48-L58
    case server
    when 's.whatsapp.net', 'c.us'
      'user'
    when 'g.us'
      'group'
    when 'lid'
      'lid'
    when 'broadcast'
      jid.start_with?('status@') ? 'status' : 'broadcast'
    when 'newsletter'
      'newsletter'
    when 'call'
      'call'
    else
      'unknown'
    end
  end

  def message_type # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize
    msg = @raw_message[:message]
    if msg.key?(:conversation) || msg.dig(:extendedTextMessage, :text).present?
      'text'
    elsif msg.key?(:imageMessage)
      'image'
    elsif msg.key?(:audioMessage)
      'audio'
    elsif msg.key?(:videoMessage)
      'video'
    elsif msg.key?(:documentMessage) || msg.key?(:documentWithCaptionMessage)
      'file'
    elsif msg.key?(:stickerMessage)
      'sticker'
    elsif msg.key?(:reactionMessage)
      'reaction'
    elsif msg.key?(:editedMessage)
      'edited'
    elsif msg.key?(:contactMessage)
      match_phone_number = msg.dig(:contactMessage, :vcard)&.match(/waid=(\d+)/)
      match_phone_number ? 'contact' : 'unsupported'
    elsif msg.key?(:protocolMessage)
      'protocol'
    elsif msg.key?(:messageContextInfo) && msg.keys.count == 1
      'context'
    else
      'unsupported'
    end
  end

  def message_content # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
    case message_type
    when 'text'
      @raw_message.dig(:message, :conversation) || @raw_message.dig(:message, :extendedTextMessage, :text)
    when 'image'
      @raw_message.dig(:message, :imageMessage, :caption)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :caption)
    when 'file'
      @raw_message.dig(:message, :documentMessage, :caption).presence ||
        @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :caption)
    when 'reaction'
      @raw_message.dig(:message, :reactionMessage, :text)
    when 'contact'
      # FIXME: Missing specs
      display_name = @raw_message.dig(:message, :contactMessage, :displayName)
      vcard = @raw_message.dig(:message, :contactMessage, :vcard)
      match_phone_number = vcard&.match(/waid=(\d+)/)

      return display_name unless match_phone_number
      return match_phone_number[1] if display_name&.start_with?('+')

      "#{display_name} - #{match_phone_number[1]}" if match_phone_number
    end
  end

  def file_content_type
    return :image if message_type.in?(%w[image sticker])
    return :video if message_type.in?(%w[video video_note])
    return :audio if message_type == 'audio'

    :file
  end

  def message_mimetype
    case message_type
    when 'image'
      @raw_message.dig(:message, :imageMessage, :mimetype)
    when 'sticker'
      @raw_message.dig(:message, :stickerMessage, :mimetype)
    when 'video'
      @raw_message.dig(:message, :videoMessage, :mimetype)
    when 'audio'
      @raw_message.dig(:message, :audioMessage, :mimetype)
    when 'file'
      @raw_message.dig(:message, :documentMessage, :mimetype).presence ||
        @raw_message.dig(:message, :documentWithCaptionMessage, :message, :documentMessage, :mimetype)
    end
  end

  def phone_number_from_jid
    reference_field = jid_type == 'lid' ? :senderPn : :remoteJid
    jid = @raw_message[:key][reference_field]
    return unless jid

    # NOTE: jid shape is `<user>_<agent>:<device>@<server>`
    # https://github.com/WhiskeySockets/Baileys/blob/v6.7.16/src/WABinary/jid-utils.ts#L19
    jid.split('@').first.split(':').first.split('_').first
  end

  def contact_name
    # NOTE: `verifiedBizName` is only available for business accounts and has a higher priority than `pushName`.
    name = @raw_message[:verifiedBizName].presence || @raw_message[:pushName]
    return name if name.presence && (self_message? || incoming?)

    phone_number_from_jid
  end

  def self_message?
    # TODO: Handle denormalized Brazilian phone numbers
    phone_number_from_jid == inbox.channel.phone_number.delete('+')
  end

  def ignore_message?
    message_type.in?(%w[protocol context edited]) ||
      (message_type == 'reaction' && message_content.blank?)
  end

  def fetch_profile_picture_url(phone_number)
    jid = "#{phone_number}@s.whatsapp.net"
    response = inbox.channel.provider_service.get_profile_pic(jid)
    response&.dig('data', 'profilePictureUrl')
  rescue StandardError => e
    Rails.logger.error "Failed to fetch profile picture for #{phone_number}: #{e.message}"
    nil
  end

  def try_update_contact_avatar
    # TODO: Current logic will never update the contact avatar if their profile picture changes on WhatsApp.
    return if @contact.avatar.attached?

    profile_pic_url = fetch_profile_picture_url(phone_number_from_jid)
    ::Avatar::AvatarFromUrlJob.perform_later(@contact, profile_pic_url) if profile_pic_url
  end

  def message_under_process?
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    Redis::Alfred.get(key)
  end

  def cache_message_source_id_in_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    ::Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    ::Redis::Alfred.delete(key)
  end
end
