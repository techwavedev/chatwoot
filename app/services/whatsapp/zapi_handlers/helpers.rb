module Whatsapp::ZapiHandlers::Helpers
  include Whatsapp::IncomingMessageServiceHelpers

  private

  def raw_message_id
    @raw_message[:isEdit] ? @raw_message[:editMessageId] : @raw_message[:messageId]
  end

  def incoming_message?
    !@raw_message[:fromMe]
  end

  def cache_message_source_id_in_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    Redis::Alfred.setex(key, true)
  end

  def clear_message_source_id_from_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    Redis::Alfred.delete(key)
  end

  def message_under_process?
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: raw_message_id)
    Redis::Alfred.get(key)
  end
end
