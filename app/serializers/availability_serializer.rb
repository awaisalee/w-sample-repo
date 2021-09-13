class AvailabilitySerializer < ActiveModel::Serializer
  attributes :id,
             :book_from_profile,
             :collect_payment,
             :session_length,
             :price,
             :timezone

  has_many :slots
end
