class SlotSerializer < ActiveModel::Serializer
  attributes :id,
             :availability_id,
             :day,
             :start_time,
             :end_time,
             :state
end
