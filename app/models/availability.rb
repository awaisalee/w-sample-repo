class Availability < ApplicationRecord
  belongs_to :user
  has_many :slots, dependent: :destroy

  accepts_nested_attributes_for :slots, allow_destroy: true
end
