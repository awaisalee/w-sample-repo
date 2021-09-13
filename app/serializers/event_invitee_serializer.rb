class EventInviteeSerializer < ActiveModel::Serializer
  attributes :id,
             :invitee_id,  # instance of user_id
             :event_id,
             :i_name,
             :i_email
end
