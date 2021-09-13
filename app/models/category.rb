class Category < ApplicationRecord
  validates :title, length: { maximum: 256 }, allow_blank: false,
            uniqueness: { case_sensitive: false }
  has_many :sub_categories

end
