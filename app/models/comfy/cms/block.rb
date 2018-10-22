class Comfy::Cms::Block < ActiveRecord::Base
  self.table_name = 'comfy_cms_blocks'

  FILE_CLASSES = %w[ActionDispatch::Http::UploadedFile
                    Rack::Test::UploadedFile File].freeze

  attr_accessor :temp_files

  # -- Relationships --------------------------------------------------------
  belongs_to :blockable,
             polymorphic: true

  has_many :files,
           autosave: true,
           dependent: :destroy

  # -- Callbacks ------------------------------------------------------------
  before_save :prepare_files

  # -- Validations ----------------------------------------------------------
  validates :identifier, presence: true

  # -- Instance Methods -----------------------------------------------------
  # Tag object that is using this block
  def tag
    @tag ||= blockable.tags(:reload).detect do |t|
      t.is_cms_block? && t.identifier == identifier
    end
  end

  # Intercepting assigns as we can't cram files into content directly anymore
  def content=(value)
    self.temp_files = [value].flatten.select do |f|
      FILE_CLASSES.member?(f.class.name)
    end
    # correctly triggering dirty
    if temp_files.present?
      write_attribute(:content, nil)
      content_will_change!
    else
      write_attribute(:content, value)
    end
  end

  protected

  # If we're passing actual files into content attribute, let's build them.
  def prepare_files
    return if temp_files.blank?

    restrict_to_single_file! if pagefile?

    temp_files.each do |file|
      files.build(
        site: blockable.site,
        dimensions: tag.try(:dimensions),
        file: file
      )
    end
  end

  def pagefile?
    tag.instance_of?(ComfortableMexicanSofa::Tag::PageFile)
  end

  def restrict_to_single_file!
    self.temp_files = [temp_files.first].compact
    files.each(&:mark_for_destruction)
  end
end
