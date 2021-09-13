class EventModeratorSerializer < ActiveModel::Serializer
  attributes :id,
             :moderator_id,  # instance of user_id
             :event_id,
             :m_name,
             :m_email
end
