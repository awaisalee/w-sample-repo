class Event < ApplicationRecord

  belongs_to :category, optional: true
  belongs_to :sub_category, class_name: "Category", foreign_key: "sub_category_id", optional: true
  belongs_to :room

  attr_accessor :skip_callbacks

  enum event_type: { meeting: 0, event: 1 }
  enum security: { locked_room: 0, room_with_a_lobby: 1, registered_guests_only: 2, padlocked_room: 3, custom: 4 }
  enum pricing_type: { free: 0, sell_tickets: 1 }
  enum recurrence_type: { weekly: 0, daily: 1 }
  enum recurrence_end_type: { with_date: 0, with_meeting: 1 }
  DAYS_OF_WEEK = %w[Sun Mon Tue Wed Thu Fri Sat]

  has_many :event_dates, dependent: :destroy
  has_many :event_invitees, dependent: :destroy
  has_many :event_speakers, dependent: :destroy
  has_many :event_moderators, dependent: :destroy

  accepts_nested_attributes_for :event_speakers, allow_destroy: true
  accepts_nested_attributes_for :event_dates, allow_destroy: true
  accepts_nested_attributes_for :event_moderators, allow_destroy: true
  accepts_nested_attributes_for :event_invitees, allow_destroy: true

  before_commit :create_recurring_events, on: :create, unless: :skip_callbacks

  private

  def create_recurring_events
    if recurrence
      event_date = event_dates.first
      start_date = event_date.start_date
      meeting_span = event_date.end_date - event_date.start_date

      if recurrence_type == 'weekly'
        week_days = recurrence_days.split(',').map(&:strip)
        week_days_sym = week_days.map { |d| Date::DAYNAMES[DAYS_OF_WEEK.index(d)].downcase.to_sym }
      end

      recurring_dates = if recurrence_type == 'weekly'
        Montrose.weekly.starting(start_date.to_date + 1.day).on(week_days_sym)
      elsif recurrence_type == 'daily'
        Montrose.daily.starting(start_date + 1.day)
      end

      if recurrence_end_type == 'with_meeting'
        recurring_dates = recurring_dates.take(recurrence_meetings)
      elsif recurrence_end_type == 'with_date'
        recurring_dates = recurring_dates.until(recurrence_end_date)
      end

      recurring_dates.each do |date|
        event = self.dup
        event.skip_callbacks = true
        event.save

        # duplicate event related data
        event.event_dates.create(start_date: date, end_date: date + meeting_span.seconds)
        event.event_speakers = event_speakers.map(&:dup)
        event.event_moderators = event_moderators.map(&:dup)
        event.event_invitees = event_invitees.map(&:dup)
      end
    end
  end

end
