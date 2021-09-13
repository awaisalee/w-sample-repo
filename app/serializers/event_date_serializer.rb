class EventDateSerializer < ActiveModel::Serializer
  attributes :id,
             :event_id,
             :start_date,
             :end_date
             
  belongs_to :event
end
