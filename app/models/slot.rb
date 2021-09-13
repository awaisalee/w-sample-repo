class Slot < ApplicationRecord
  belongs_to :availability

  enum day: { monday: 0, tuesday: 1, wednesday: 2, thursday: 3, friday: 4, saturday: 5, sunday: 6}
  enum state: { available: 0, booked: 1, canceled: 2 }
end
