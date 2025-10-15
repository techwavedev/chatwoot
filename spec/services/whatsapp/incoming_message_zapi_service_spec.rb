require 'rails_helper'

describe Whatsapp::IncomingMessageZapiService do
  describe '#perform' do
    let!(:whatsapp_channel) do
      create(:channel_whatsapp, provider: 'zapi', validate_provider_config: false, received_messages: false)
    end
    let(:inbox) { whatsapp_channel.inbox }

    context 'when type is blank' do
      it 'does nothing' do
        params = { type: '' }

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(Message, :count)
      end

      it 'does nothing when type is nil' do
        params = {}

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(Message, :count)
      end
    end

    context 'when event type is unsupported' do
      it 'logs a warning message' do
        params = { type: 'unsupported_event' }
        allow(Rails.logger).to receive(:warn)

        described_class.new(inbox: inbox, params: params).perform

        expect(Rails.logger).to have_received(:warn).with(/Z-API unsupported event/)
      end
    end

    context 'when processing connected_callback event' do
      let(:params) do
        {
          type: 'ConnectedCallback',
          phone: whatsapp_channel.phone_number.delete('+')
        }
      end

      it 'updates provider connection to open when phone numbers match' do
        described_class.new(inbox: inbox, params: params).perform

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('open')
      end

      it 'updates provider connection to close when phone numbers do not match' do
        params[:phone] = '5511123456789'
        allow(whatsapp_channel).to receive(:disconnect_channel_provider)

        described_class.new(inbox: inbox, params: params).perform

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')
        expect(whatsapp_channel.provider_connection['error']).to eq(I18n.t('errors.inboxes.channel.provider_connection.wrong_phone_number'))
        expect(whatsapp_channel).to have_received(:disconnect_channel_provider)
      end

      it 'handles Brazil mobile number normalization' do
        whatsapp_channel.update!(phone_number: '+5511987654321')
        params[:phone] = '551187654321' # Without leading digit '9'

        described_class.new(inbox: inbox, params: params).perform

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('open')
      end
    end

    context 'when processing disconnected_callback event' do
      let(:params) { { type: 'DisconnectedCallback' } }

      it 'updates provider connection to close' do
        described_class.new(inbox: inbox, params: params).perform

        expect(whatsapp_channel.reload.provider_connection['connection']).to eq('close')
      end
    end

    context 'when processing received_callback event' do
      let(:contact_phone) { '+5511987654321' }
      let(:message_id) { 'msg_123' }
      let(:contact) { create(:contact, phone_number: contact_phone, account: inbox.account) }
      let(:params) do
        {
          type: 'ReceivedCallback',
          messageId: message_id,
          momment: Time.current.to_i * 1000,
          phone: '5511987654321',
          fromMe: false,
          messageType: 'chat',
          text: { message: 'Hello World' }
        }
      end

      it 'creates a new message when message does not exist' do
        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.to change(Message, :count).by(1)

        message = Message.last
        expect(message.content).to eq('Hello World')
        expect(message.source_id).to eq(message_id)
        expect(message.message_type).to eq('incoming')
      end

      it 'does not create duplicate messages' do
        described_class.new(inbox: inbox, params: params).perform

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(Message, :count)
      end

      it 'handles edited messages' do
        described_class.new(inbox: inbox, params: params).perform
        original_message = Message.last
        edited_params = params.merge(
          isEdit: true,
          text: { message: 'Hello World - Edited' }
        )

        described_class.new(inbox: inbox, params: edited_params).perform

        expect(original_message.reload.content).to eq('Hello World - Edited')
        expect(original_message.content_attributes['is_edited']).to be(true)
        expect(original_message.content_attributes['previous_content']).to eq('Hello World')
      end

      it 'calls channel received_messages method for incoming messages' do
        allow(inbox.channel).to receive(:received_messages)
        described_class.new(inbox: inbox, params: params).perform

        message = Message.last
        conversation = message.conversation
        expect(inbox.channel).to have_received(:received_messages).with([message], conversation)
      end

      context 'when processing image message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'img_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            messageType: 'image',
            image: {
              caption: 'Check this image',
              imageUrl: 'https://example.com/image.jpg',
              mimeType: 'image/jpeg'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/image.jpg')
            .to_return(status: 200, body: 'fake image data', headers: { 'Content-Type' => 'image/jpeg' })
        end

        it 'creates message with image attachment' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('Check this image')
          expect(message.attachments.count).to eq(1)
          expect(message.attachments.first.file_type).to eq('image')
        end
      end

      context 'when processing audio message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'audio_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            messageType: 'audio',
            audio: {
              audioUrl: 'https://example.com/audio.mp3',
              mimeType: 'audio/mpeg'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/audio.mp3')
            .to_return(status: 200, body: 'fake audio data', headers: { 'Content-Type' => 'audio/mpeg' })
        end

        it 'creates message with audio attachment' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.attachments.count).to eq(1)
          expect(message.attachments.first.file_type).to eq('audio')
        end
      end

      context 'when processing video message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'video_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            messageType: 'video',
            video: {
              caption: 'Check this video',
              videoUrl: 'https://example.com/video.mp4',
              mimeType: 'video/mp4'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/video.mp4')
            .to_return(status: 200, body: 'fake video data', headers: { 'Content-Type' => 'video/mp4' })
        end

        it 'creates message with video attachment' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('Check this video')
          expect(message.attachments.count).to eq(1)
          expect(message.attachments.first.file_type).to eq('video')
        end
      end

      context 'when processing document message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'doc_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            messageType: 'document',
            document: {
              caption: 'Important document',
              documentUrl: 'https://example.com/document.pdf',
              fileName: 'document.pdf',
              mimeType: 'application/pdf'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/document.pdf')
            .to_return(status: 200, body: 'fake pdf data', headers: { 'Content-Type' => 'application/pdf' })
        end

        it 'creates message with document attachment' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('document.pdf')
          expect(message.attachments.count).to eq(1)
          expect(message.attachments.first.file_type).to eq('file')
        end
      end

      context 'when processing unsupported message type' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'unsupported_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            messageType: 'unsupported',
            data: 'some unsupported data'
          }
        end

        it 'creates message marked as unsupported' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to be_blank
          expect(message.is_unsupported).to be(true)
        end
      end

      context 'when processing reaction message' do
        let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511987654321') }
        let(:conversation) { create(:conversation, inbox: inbox, contact_inbox: contact_inbox) }
        let!(:original_message) { create(:message, inbox: inbox, conversation: conversation, source_id: 'original_123') } # rubocop:disable RSpec/LetSetup
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'reaction_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            reaction: {
              value: '👍',
              referencedMessage: { messageId: 'original_123' }
            }
          }
        end

        it 'creates reaction message' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('👍')
          expect(message.content_attributes[:is_reaction]).to be(true)
          expect(message.content_attributes[:in_reply_to_external_id]).to eq('original_123')
        end

        it 'creates empty reaction message' do
          params[:reaction][:value] = ''

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('')
          expect(message.content_attributes[:is_reaction]).to be(true)
        end
      end

      context 'when processing sticker message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'sticker_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            sticker: {
              stickerUrl: 'https://example.com/sticker.webp',
              mimeType: 'image/webp'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/sticker.webp')
            .to_return(status: 200, body: 'fake sticker data', headers: { 'Content-Type' => 'image/webp' })
        end

        it 'creates message with sticker attachment' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.attachments.count).to eq(1)
          expect(message.attachments.first.file_type).to eq('image')
        end
      end

      context 'when processing outgoing message' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'outgoing_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: true,
            text: { message: 'Outgoing message' }
          }
        end

        before do
          create(:account_user, account: inbox.account)
        end

        it 'creates outgoing message' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.content).to eq('Outgoing message')
          expect(message.message_type).to eq('outgoing')
        end

        it 'does not call channel received_messages method for outgoing messages' do
          allow(inbox.channel).to receive(:received_messages)

          described_class.new(inbox: inbox, params: params).perform

          expect(inbox.channel).not_to have_received(:received_messages)
        end
      end

      context 'when handling duplicated events' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'duplicate_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            text: { message: 'Duplicated event' }
          }
        end

        it 'does not create message if it is already being processed' do
          allow(Redis::Alfred).to receive(:get)
            .with(format_message_source_key('duplicate_123'))
            .and_return(true)

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to change(Message, :count)
        end

        it 'caches and clears message source id in Redis' do
          allow(Redis::Alfred).to receive(:setex)
          allow(Redis::Alfred).to receive(:delete)

          described_class.new(inbox: inbox, params: params).perform

          expect(Redis::Alfred).to have_received(:setex)
            .with(format_message_source_key('duplicate_123'), true)
          expect(Redis::Alfred).to have_received(:delete)
            .with(format_message_source_key('duplicate_123'))
        end
      end

      context 'when attachment download fails' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'img_fail_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            image: {
              caption: 'Failed image',
              imageUrl: 'https://example.com/broken.jpg',
              mimeType: 'image/jpeg'
            }
          }
        end

        before do
          allow(Down).to receive(:download).and_raise(Down::ResponseError.new('Download failed'))
          allow(Rails.logger).to receive(:error)
        end

        it 'creates message marked as unsupported when download fails' do
          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.is_unsupported).to be(true)
          expect(Rails.logger).to have_received(:error).with(/Failed to download attachment/)
        end

        it 'handles malformed attachment URLs gracefully' do
          allow(Down).to receive(:download).and_raise(Down::InvalidUrl.new('Invalid URL'))

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.is_unsupported).to be(true)
        end

        it 'handles network timeout errors' do
          allow(Down).to receive(:download).and_raise(Down::TimeoutError.new('Download timeout'))

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.to change(Message, :count).by(1)

          message = Message.last
          expect(message.is_unsupported).to be(true)
        end
      end

      context 'when contact name handling' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'name_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654322',
            fromMe: false,
            senderName: 'John Doe from Z-API',
            text: { message: 'Hello with name' }
          }
        end

        it 'creates contact with sender name when provided' do
          described_class.new(inbox: inbox, params: params).perform

          contact = Contact.last
          expect(contact.name).to eq('John Doe from Z-API')
        end

        it 'uses phone number as name when sender name is not provided' do
          params.delete(:senderName)

          described_class.new(inbox: inbox, params: params).perform

          message = Message.last
          expect(message.sender.name).to eq('5511987654322')
        end
      end

      context 'when message should not be processed' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'filtered_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            text: { message: 'Filtered message' }
          }
        end

        it 'does not process group messages' do
          params[:isGroup] = true

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to change(Message, :count)
        end

        it 'does not process newsletter messages' do
          params[:isNewsletter] = true

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to change(Message, :count)
        end

        it 'does not process broadcast messages' do
          params[:broadcast] = true

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to change(Message, :count)
        end

        it 'does not process status reply messages' do
          params[:isStatusReply] = true

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to change(Message, :count)
        end
      end

      context 'when processing attachment with file extensions' do
        let(:params) do
          {
            type: 'ReceivedCallback',
            messageId: 'ext_123',
            momment: Time.current.to_i * 1000,
            phone: '5511987654321',
            fromMe: false,
            document: {
              fileName: 'report.xlsx',
              documentUrl: 'https://example.com/report.xlsx',
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
            }
          }
        end

        before do
          stub_request(:get, 'https://example.com/report.xlsx')
            .to_return(status: 200, body: 'fake excel data',
                       headers: { 'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
        end

        it 'preserves original filename and extension' do
          described_class.new(inbox: inbox, params: params).perform

          message = Message.last
          attachment = message.attachments.first
          expect(attachment.file.filename.to_s).to eq('report.xlsx')
          expect(attachment.file.content_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        end
      end
    end

    context 'when processing delivery_callback event' do
      let(:message) { create(:message, inbox: inbox, source_id: 'msg_456') }
      let(:params) do
        {
          type: 'DeliveryCallback',
          messageId: message.source_id,
          momment: Time.current.to_i * 1000
        }
      end

      it 'updates message status to delivered' do
        described_class.new(inbox: inbox, params: params).perform

        expect(message.reload.status).to eq('delivered')
        expect(message.external_created_at).to eq(params[:momment] / 1000)
      end

      it 'updates message status to failed when error is present' do
        params[:error] = 'Message delivery failed'

        described_class.new(inbox: inbox, params: params).perform

        expect(message.reload.status).to eq('failed')
        expect(message.external_error).to eq('Message delivery failed')
      end

      it 'does nothing when message is not found' do
        params[:messageId] = 'non_existent_message'

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to change(message, :status)
      end
    end

    context 'when processing message_status_callback event' do
      let(:message1) { create(:message, inbox: inbox, source_id: 'msg_123') }
      let(:message2) { create(:message, inbox: inbox, source_id: 'msg_456') }
      let(:params) do
        {
          type: 'MessageStatusCallback',
          ids: [message1.source_id, message2.source_id],
          status: 'SENT'
        }
      end

      it 'updates message status to sent when Z-API status is SENT' do
        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('sent')
        expect(message2.reload.status).to eq('sent')
      end

      it 'updates message status to delivered for DELIVERED status' do
        params[:status] = 'DELIVERED'

        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('delivered')
        expect(message2.reload.status).to eq('delivered')
      end

      it 'updates message status to delivered for RECEIVED status' do
        params[:status] = 'RECEIVED'

        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('delivered')
        expect(message2.reload.status).to eq('delivered')
      end

      it 'updates message status to read for READ status' do
        params[:status] = 'READ'

        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('read')
        expect(message2.reload.status).to eq('read')
      end

      it 'updates message status to read for READ_BY_ME status' do
        params[:status] = 'READ_BY_ME'

        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('read')
        expect(message2.reload.status).to eq('read')
      end

      it 'updates message status to read for PLAYED status' do
        params[:status] = 'PLAYED'

        described_class.new(inbox: inbox, params: params).perform

        expect(message1.reload.status).to eq('read')
        expect(message2.reload.status).to eq('read')
      end

      it 'does not update status on unknown status and logs warning' do
        params[:status] = 'UNKNOWN_STATUS'
        allow(Rails.logger).to receive(:warn)

        expect do
          described_class.new(inbox: inbox, params: params).perform
        end.not_to(change { [message1.reload.status, message2.reload.status] })

        expect(Rails.logger).to have_received(:warn).with('Unknown ZAPI status: UNKNOWN_STATUS')
      end

      context 'when status transition is not allowed' do
        it 'does not downgrade read message to delivered' do
          message1.update!(status: 'read')
          params[:status] = 'DELIVERED'

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to(change { message1.reload.status })
        end

        it 'does not downgrade read message to sent' do
          message1.update!(status: 'read')
          params[:status] = 'SENT'

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to(change { message1.reload.status })

          expect(message1.status).to eq('read')
        end

        it 'does not downgrade delivered message to sent' do
          message1.update!(status: 'delivered')
          params[:status] = 'SENT'

          expect do
            described_class.new(inbox: inbox, params: params).perform
          end.not_to(change { message1.reload.status })

          expect(message1.status).to eq('delivered')
        end

        it 'allows upgrading delivered message to read' do
          message1.update!(status: 'delivered')
          params[:status] = 'READ'

          described_class.new(inbox: inbox, params: params).perform

          expect(message1.reload.status).to eq('read')
        end

        it 'allows upgrading sent message to delivered' do
          message1.update!(status: 'sent')
          params[:status] = 'DELIVERED'

          described_class.new(inbox: inbox, params: params).perform

          expect(message1.reload.status).to eq('delivered')
        end

        it 'allows upgrading sent message to read' do
          message1.update!(status: 'sent')
          params[:status] = 'READ'

          described_class.new(inbox: inbox, params: params).perform

          expect(message1.reload.status).to eq('read')
        end

        it 'handles mixed status transitions correctly' do
          message1.update!(status: 'sent')
          message2.update!(status: 'read')
          params[:status] = 'DELIVERED'

          described_class.new(inbox: inbox, params: params).perform

          expect(message1.reload.status).to eq('delivered')
          expect(message2.reload.status).to eq('read')
        end
      end
    end
  end

  private

  def format_message_source_key(message_id)
    format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: message_id)
  end
end
