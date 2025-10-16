module Whatsapp::ZapiHandlers::ConnectedCallback
  include Whatsapp::ZapiHandlers::Helpers

  private

  def process_connected_callback
    expected_phone_number = inbox.channel.phone_number.delete('+')
    received_phone_number = processed_params[:phone]

    if normalised_brazil_mobile_number(expected_phone_number) != normalised_brazil_mobile_number(received_phone_number)
      inbox.channel.update_provider_connection!(connection: 'close',
                                                error: I18n.t('errors.inboxes.channel.provider_connection.wrong_phone_number'))

      inbox.channel.disconnect_channel_provider
      return
    end

    inbox.channel.update_provider_connection!(connection: 'open')
  end
end
