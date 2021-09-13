class EventSerializer < ActiveModel::Serializer
  attributes :id,
             :subject,
             :description,
             :timezone,
             :category_id,
             :sub_category_id,
             :room_id,
             :event_type,
             :security,
             :pricing_type,
             :price,
             :webinar_mode,
             :limited_slots,
             :no_of_slots,
             :recurrence,
             :recurrence_type,
             :recurrence_end_type,
             :recurrence_end_date,
             :recurrence_days,
             :recurrence_meetings,
             :is_private,
             :allow_participants_to_share,
             :mute_participants

  has_many :event_dates
  has_many :event_moderators
  has_many :event_invitees
  has_many :event_speakers
  belongs_to :room
  belongs_to :category
end
