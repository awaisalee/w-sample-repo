class Appointment < ApplicationRecord
  include Emailer
  include Deleteable

  attr_accessor :new_participants
  attr_accessor :skip_callbacks

  belongs_to :user
  has_many :participants, after_add: :add_new_participants
  default_scope { order(start_date: :desc) }

  validates_presence_of :start_date
  validate :end_date_is_after_start_date

  accepts_nested_attributes_for :participants, reject_if: :email_invalid, allow_destroy: true

  after_commit :send_create_meeting_invite, on: :create, unless: :skip_callbacks
  after_commit :send_update_meeting_invite, on: :update, unless: :skip_callbacks
  after_destroy :send_dropped_invite, unless: :skip_callbacks
  before_save :init_recurring_id, unless: :skip_callbacks
  after_commit :create_recurring_events, on: :create, unless: :skip_callbacks

  enum recurring_type: { weekly: 0, daily: 1 }
  enum recurring_end_type: { with_date: 0, with_meeting: 1 }
  DAYS_OF_WEEK= %w[Sun Mon Tue Wed Thu Fri Sat]
  DAYS_OF_WEEK_SYM= %w[sunday monday tuesday wednesday thursday friday saturday]

  before_save do
    self.recurring_days.gsub!(/[\[\]\"]/, "") if attribute_present?("recurring_days")
  end

  def self.get_appointments user
    joins(:participants).where("appointments.end_date >= ?", DateTime.now).where("participants.email = ? OR appointments.user_id = ?", user.email, user.id).reorder('appointments.start_date ASC').distinct
  end

  def send_create_meeting_invite
    send_meeting_invitation_email(self, user, 'create')
    participants.each do |participant|
      send_meeting_invitation_email(self, participant, 'create')
    end
  end

  def send_update_meeting_invite
    if name_previously_changed? || start_date_previously_changed? || end_date_previously_changed?
      send_meeting_invitation_email(self, user, 'update')
      participants.where.not(id: new_participants).each do |participant|
        send_meeting_invitation_email(self, participant, 'update')
      end
    end
    new_participants.each do |participant|
      send_meeting_invitation_email(self, participant, 'create')
    end
  end

  def send_dropped_invite
    send_meeting_dropped_email(self, user)
    participants.each do |participant|
      send_meeting_dropped_email(self, participant)
      participant.delete
    end
  end

  def send_meeting_dropped_email_to participant
    send_meeting_dropped_email(self, participant)
  end

  def init_recurring_id
    self.recurring_id = SecureRandom.uuid if self.recurring_id.blank?
  end

  def start_time
    start_date&.strftime("%I:%M %p")
  end

  def end_time
    end_date&.strftime("%I:%M %p")
  end

  private
  def email_invalid(attributes)
    (attributes['email'] =~ URI::MailTo::EMAIL_REGEXP).nil?
  end

  def end_date_is_after_start_date
    return false if end_date.blank? || start_date.blank?
    if end_date < start_date
      errors.add(:end_date, "cannot be before the start date")
    end
  end

  def add_new_participants participant
    new_participants.push(participant)
  end

  def new_participants
    @new_participants.nil? ? @new_participants = [] : @new_participants
  end

  def room
    user.rooms.first
  end

  def create_recurring_events
    if self.recurring
      date = self.start_date
      meeting_span = self.end_date - self.start_date

      if self.recurring_type == 'weekly'
        week_days = self.recurring_days.split(',').map(&:strip)
        week_days_sym = week_days.map{|d| Date::DAYNAMES[DAYS_OF_WEEK.index(d)].downcase.to_sym}
      end

      recurrence = if self.recurring_type == 'weekly'
        Montrose.weekly.starting(date).on(week_days_sym)
      elsif self.recurring_type == 'daily'
        Montrose.daily.starting(date)
      end

      if self.recurring_end_type == 'with_meeting'
        recurrence = recurrence.take(self.recurring_meetings)
      elsif self.recurring_end_type == 'with_date'
        recurrence = recurrence.until(self.recurring_end_date)
      end

      recurrence.each do |r_date|
        next if r_date == date
        appointment = self.dup
        appointment.skip_callbacks = true
        appointment.start_date = r_date
        appointment.end_date = r_date + meeting_span.seconds
        appointment.save
        appointment.participants = self.participants.map(&:dup)
      end
    end
  end
end
