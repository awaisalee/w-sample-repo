class RoomUrlBackup < ApplicationRecord
  belongs_to :room, optional: true
end
