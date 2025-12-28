class Whatsapp::Providers::WhatsappBaileysService < Whatsapp::Providers::BaseService
  include BaileysHelper

  class MessageContentTypeNotSupported < StandardError; end
  class ProviderUnavailableError < StandardError; end

  DEFAULT_CLIENT_NAME = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_CLIENT_NAME', 'Chatwoot')
  DEFAULT_URL = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_URL', 'http://baileys:3000')
  DEFAULT_API_KEY = ENV.fetch('BAILEYS_PROVIDER_DEFAULT_API_KEY', nil)

  def self.status
    # WAHA readiness check
    response = HTTParty.get("#{DEFAULT_URL}/api/sessions", headers: default_api_headers)
    
    unless response.success?
      Rails.logger.error "WAHA Status Check Failed: #{response.body}"
      raise ProviderUnavailableError, 'WAHA API is unavailable'
    end

    { status: 'ok', version: 'waha' }
  rescue StandardError => e
    Rails.logger.error e.message
    raise ProviderUnavailableError, 'WAHA API is unavailable'
  end

  def setup_channel_provider
    # Start a session in WAHA
    response = HTTParty.post(
      "#{provider_url}/api/sessions",
      headers: api_headers,
      body: {
        name: session_name,
        config: {
          webhookUrl: whatsapp_channel.inbox.callback_webhook_url,
          webhookEvents: ['message', 'message.any', 'state.change'] 
        }
      }.to_json
    )

    # WAHA returns 201 Created or 409 Conflict (if already exists)
    return true if response.success? || response.code == 409

    Rails.logger.error "WAHA Session Setup Failed: #{response.body}"
    raise ProviderUnavailableError
  end

  def disconnect_channel_provider
    # Logout/Stop session in WAHA
    response = HTTParty.post(
      "#{provider_url}/api/sessions/#{session_name}/logout",
      headers: api_headers
    )

    return true if response.success? || response.code == 404

    Rails.logger.error "WAHA Session Disconnect Failed: #{response.body}"
    raise ProviderUnavailableError
  end

  def send_message(recipient_id, message)
    @message = message
    @recipient_id = recipient_id
    
    # Format phone number for WAHA (chatId)
    chat_id = remote_jid

    payload = {
      chatId: chat_id,
      session: session_name
    }

    if @message.attachments.present?
      # Handle Attachment
      attachment = @message.attachments.first
      payload[:file] = {
        mimetype: attachment.file.content_type,
        filename: attachment.file.filename,
        url: attachment_url(attachment) 
      }
      payload[:caption] = @message.outgoing_content if @message.outgoing_content.present?
      endpoint = "send/file"
    elsif @message.outgoing_content.present?
      # Text Message
      payload[:text] = @message.outgoing_content
      endpoint = "send/text"
    else
      @message.update!(is_unsupported: true)
      return
    end

    response = HTTParty.post(
      "#{provider_url}/api/#{endpoint}",
      headers: api_headers,
      body: payload.to_json
    )

    if response.success?
       # Update message with external ID if available
       update_external_created_at(response)
       return response.parsed_response['id']
    else
       Rails.logger.error "WAHA Send Message Failed: #{response.body}"
       raise ProviderUnavailableError
    end
  end

  # Helper to get attachment URL (assumes Chatwoot can serve it publicly or internal network)
  def attachment_url(attachment)
    # Using the standard Rails URL helper/service or blob url
    # Ensure this URL is accessible by the WAHA container
    attachment.download_url
  end

  def api_headers
    headers = { 'Content-Type' => 'application/json' }
    headers['X-Api-Key'] = api_key if api_key.present?
    headers
  end

  def self.default_api_headers
    headers = { 'Content-Type' => 'application/json' }
    headers['X-Api-Key'] = DEFAULT_API_KEY if DEFAULT_API_KEY.present?
    headers
  end

  # Other methods (stubbed or adapted)
  def validate_provider_config?
    # Check if session exists or can be listed
    response = HTTParty.get("#{provider_url}/api/sessions/#{session_name}", headers: api_headers)
    response.success?
  end

  def get_profile_pic(jid)
     # WAHA: GET /api/contacts/{session}/profile-picture?contactId={jid}
     response = HTTParty.get(
        "#{provider_url}/api/contacts/profile-picture",
        query: { session: session_name, contactId: jid },
        headers: api_headers
     )
     return nil unless response.success?
     response.parsed_response['url']
  end

  # Helpers
  
  def session_name
    # Use phone number as session name (common pattern)
    whatsapp_channel.phone_number.delete('+')
  end

  def provider_url
    whatsapp_channel.provider_config['provider_url'].presence || DEFAULT_URL
  end

  def api_key
    whatsapp_channel.provider_config['api_key'].presence || DEFAULT_API_KEY
  end

  def remote_jid
    # Ensure suffix is correct
    jid = @recipient_id.delete('+')
    jid.include?('@') ? jid : "#{jid}@s.whatsapp.net"
  end

  def update_external_created_at(response)
    # WAHA might return 'timestamp' or we use current time
    # This is optional for now
  end

  # Implement other required abstract methods with stubs or logic
  def send_template(phone_number, template_info); end
  def sync_templates; end
  def on_whatsapp(recipient_id); { 'exists' => true, 'jid' => recipient_id } end # Stub for now
  def toggle_typing_status(typing_status, recipient_id:, **); end
  def update_presence(status); end
  def read_messages(messages, recipient_id:, **); end
  def unread_message(recipient_id, message); end
  def received_messages(recipient_id, messages); end
  def media_url(media_id); "" end

end
