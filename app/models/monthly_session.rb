class MonthlySession < ApplicationRecord
  belongs_to :user
  validates :available_sessions, presence: true
  validates :month, presence: true, numericality: { only_integer: true }
  validates :year, presence: true, numericality: { only_integer: true }
  validates :user_id, presence: true, numericality: { only_integer: true }

end
