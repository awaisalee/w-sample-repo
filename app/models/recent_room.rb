class RecentRoom < ApplicationRecord
  default_scope { order(last_joined_at: :desc) }
  belongs_to :user
  belongs_to :room
  scope :saved, -> { where(saved: true) }

  after_save :touch_last_joined, on: :commit

  def touch_last_joined
    if saved_previously_changed?
      update_column('last_joined_at', DateTime.now)
    end
  end
end
