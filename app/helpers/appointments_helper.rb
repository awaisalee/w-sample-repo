module AppointmentsHelper
  def checked(day)
    @appointment.recurring_days.nil? ? false : @appointment.recurring_days.match(day)
  end

  def checked_recurring_end_type(type)
    @appointment.recurring_end_type.nil? ? false : @appointment.recurring_end_type.match(type)
  end

  def time_slots
    slots = []
    %W[AM PM].each do |merid|
      %W[12 01 02 03 04 05 06 07 08 09 10 11].each do |hrs|
        %W[00 15 30 45].each do |min|
          slots << "#{hrs}:#{min} #{merid}"
        end
      end
    end
    slots
  end
end
