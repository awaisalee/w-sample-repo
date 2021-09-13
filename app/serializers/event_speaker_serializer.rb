class EventSpeakerSerializer < ActiveModel::Serializer
  attributes :id,
             :speaker_id,  # instance of user_id
             :event_id,
             :title,
             :s_name,
             :s_email,
             :twitter_handle,
             :instagram_handle
end
