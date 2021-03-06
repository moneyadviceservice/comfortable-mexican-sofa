# encoding: utf-8
require "transitions"
require "active_model/transitions"

class Comfy::Cms::Page < ActiveRecord::Base
  include ActiveModel::Transitions

  self.table_name = 'comfy_cms_pages'

  cms_acts_as_tree :counter_cache => :children_count
  cms_is_mirrored
  cms_is_categorized
  cms_is_regulated
  cms_manageable

  # -- Relationships --------------------------------------------------------
  belongs_to :site
  belongs_to :layout
  belongs_to :target_page,
    :class_name => 'Comfy::Cms::Page'
  has_many :revisions,
     as:         :record,
     dependent:  :destroy,
     class_name: 'Comfy::Cms::Revision'

  # The active_revision points to a revision that is treated as live
  # in the case of editing published articles, or scheduling future changes
  belongs_to :active_revision,
     class_name: 'Comfy::Cms::Revision'

  # -- Callbacks ------------------------------------------------------------
  before_validation :assigns_label,
                    :assign_parent,
                    :escape_slug,
                    :assign_full_path

  before_save       :cache_preview
  before_create     :assign_position
  after_save        :sync_child_full_paths!
  after_find        :unescape_slug_and_path

  # -- Validations ----------------------------------------------------------
  validates :site_id,
    :presence   => true
  validates :label,
    :presence   => true
  validates :slug,
    :presence   => true,
    :uniqueness => { :scope => :parent_id },
    :unless     => lambda{ |p| p.site && (p.site.pages.count == 0 || p.site.pages.root == self) }
  validates :layout,
    :presence   => true
  validate :validate_target_page
  validate :validate_format_of_unescaped_slug

  # -- Scopes ---------------------------------------------------------------
  default_scope -> { order('comfy_cms_pages.position') }

  # 'unsaved' is a bit of a pointless state, so lump it in with drafts
  scope :draft, -> { where(state: [:draft, :unsaved]) }

  scope :published, -> {
    joins('LEFT JOIN comfy_cms_revisions ON comfy_cms_pages.active_revision_id = comfy_cms_revisions.id').
    where(
      # Pages with state 'published'
      arel_table[:state].eq('published').

      # Or pages with state 'published_being_edited',
      # but also an active_revision
      or(
        arel_table[:state].eq('published_being_edited').
        and(Comfy::Cms::Revision.arel_table[:id].not_eq(nil))
      ).

      # Or pages with state 'scheduled' and timestamp in the past
      or(
        arel_table[:state].eq('scheduled').
        and(arel_table[:scheduled_on].lt(Time.now))
      ).

      # Or pages with state 'scheduled' and timestamp in the future,
      # but also an active_revision
      or(
        (arel_table[:state].eq('scheduled')).
        and(arel_table[:scheduled_on].gt(Time.now)).
        and(Comfy::Cms::Revision.arel_table[:id].not_eq(nil))
      )
    )
  }

  scope :published_being_edited, -> { where(state: :published_being_edited) }

  scope :scheduled, -> {
    joins('LEFT JOIN comfy_cms_revisions ON comfy_cms_pages.active_revision_id = comfy_cms_revisions.id').
    where(
      (arel_table[:state].eq('scheduled')).
      and(arel_table[:scheduled_on].gt(Time.now)).
      and(Comfy::Cms::Revision.arel_table[:id].not_eq(nil))
    )
  }

  scope :unpublished, -> { where(state: :unpublished) }

  scope :with_content_like, ->(phrase) {
    joins(:blocks).where("comfy_cms_blocks.content LIKE ?", "%#{phrase}%")
  }

  scope :with_label_like, ->(phrase) {
    where("#{table_name}.label LIKE ?", "%#{phrase}%")
  }

  scope :with_slug_like, ->(phrase) {
    where("#{table_name}.slug LIKE ?", "%#{phrase}%")
  }

  scope :with_slug, ->(slug) {
    find_by_slug(slug) || find_by_full_path!("/" + slug)
  }

  # These scopes are to be used with the Filtrable module
  scope :category, ->(category) { includes(:categories).for_category(category) }
  scope :layout, ->(layout) { joins(:layout).merge(Comfy::Cms::Layout.where(identifier: layout)) }
  scope :language, ->(language) { joins(:site).where("comfy_cms_sites.label = ?", language.to_s) }
  scope :status, ->(status) { where(state: status) }
  scope :last_edit, ->(last_edit) { all }  # FIXME: To be implemented after we add user edit info to pages

  # -- Class Methods --------------------------------------------------------
  # Tree-like structure for pages
  def self.options_for_select(site, page = nil, current_page = nil, depth = 0, exclude_self = true, spacer = '. . ')
    return [] if (current_page ||= site.pages.root) == page && exclude_self || !current_page
    out = []
    out << [ "#{spacer*depth}#{current_page.label}", current_page.id ] unless current_page == page
    current_page.children.each do |child|
      out += options_for_select(site, page, child, depth + 1, exclude_self, spacer)
    end if current_page.children_count.nonzero?
    return out.compact
  end

  # state machine
  state_machine initial: :unsaved do
    state :unsaved
    state :draft
    state :published
    state :published_being_edited
    state :unpublished
    state :scheduled

    event :create_initial_draft do
      transitions :to => :draft, :from => [:unsaved]
    end

    event :publish, :timestamp => :published_at do
      transitions :to => :published, :from => [:draft, :published_being_edited]
    end

    # We typically don't have events where the state doesn't changes
    # however we do here due to it triggering a timestamp (published_at)
    event :publish_changes, :timestamp => :published_at do
      transitions :to => :published, :from => [:published]
    end

    # Should only create a draft of a scheduled post after it's gone live (i.e. it's "published")
    event :create_new_draft, :guard => :can_create_new_draft? do
      transitions :to => :published_being_edited, :from => [:published, :scheduled]
    end

    event :schedule do
      transitions :to => :scheduled, :from => [:draft, :published_being_edited]
    end

    # This is only meant for scheduled new posts, if unscheduling an update
    # there is the event below, unschedule_update.
    event :unschedule, :guard => :can_unschedule? do
      transitions :to => :draft, :from => [:scheduled]
    end

    # This could essentially be done with the create_new_draft event but having
    # a separate event emphasises it's purpose for a different scenario.
    event :unschedule_update, :guard => :can_unschedule_update? do
      transitions :to => :published_being_edited, :from => [:scheduled]
    end

    event :unpublish do
      transitions :to => :unpublished, :from => [:published]
    end

    event :return_to_draft do
      transitions :to => :draft, :from => [:unpublished]
    end
  end

  # -- State related methods ------------------------------------------------
  def can_create_new_draft?
    published? || scheduled_on <= Time.current
  end

  def can_unschedule?
    !active_revision.present? && scheduled_on > Time.current
  end

  def can_unschedule_update?
    active_revision.present? && scheduled_on > Time.current
  end

  # -- Instance Methods -----------------------------------------------------
  # For previewing purposes sometimes we need to have full_path set. This
  # full path take care of the pages and its childs but not of the site path
  def full_path
    self.read_attribute(:full_path) || self.assign_full_path
  end

  # Somewhat unique method of identifying a page that is not a full_path
  def identifier
    self.parent_id.blank?? 'index' : self.full_path[1..-1].slugify
  end

  # Full url for a page
  def url
    "//" + "#{self.site.hostname}/#{self.site.path}/#{self.full_path}".squeeze("/")
  end

  def category_names
    categories.select(:label).map(&:label)
  end

  def layout_identifier
    layout.identifier
  end

  def as_json(options = {})
    super(
      include: {
        blocks: {
          only: [:identifier, :content, :created_at, :updated_at],
          methods: [:last_published_content]
        }
      },
      except: [:id, :layout_id, :parent_id, :target_page_id,
               :site_id, :position, :children_count,
               :content_cache, :preview_cache, :translation_id,
               :custom_slug],
      methods: [:category_names, :layout_identifier]
    )
  end

  def update_state!(state_event)
    self.send((state_event.to_s + "!").to_sym)
  end

  def update_state(state_event)
    self.send(state_event.to_sym)
  end

  def block_content
    blocks.find {|b| b.identifier == "content" }.try(:content) || ""
  end

protected

  def assigns_label
    self.label = self.label.blank?? self.slug.try(:titleize) : self.label
  end

  def assign_parent
    return unless site
    self.parent ||= site.pages.root unless self == site.pages.root || site.pages.count == 0
  end

  def assign_full_path
    if self.read_attribute(:full_path).blank?
      self.full_path = self.parent ? "#{CGI::escape(self.parent.full_path).gsub('%2F', '/')}/#{self.slug}".squeeze('/') : '/'
    end
  end

  def assign_position
    return unless self.parent
    return if self.position.to_i > 0
    max = self.parent.children.maximum(:position)
    self.position = max ? max + 1 : 0
  end

  def validate_target_page
    return unless self.target_page
    p = self
    while p.target_page do
      return self.errors.add(:target_page_id, 'Invalid Redirect') if (p = p.target_page) == self
    end
  end

  def validate_format_of_unescaped_slug
    return unless slug.present?
    unescaped_slug = CGI::unescape(self.slug)
    errors.add(:slug, :invalid) unless unescaped_slug =~ /^\p{Alnum}[\.\p{Alnum}\p{Mark}_-]*$/i
  end

  # Forcing re-saves for child pages so they can update full_paths
  def sync_child_full_paths!
    return unless full_path_changed?
    children.each do |p|
      p.update_column(:full_path, p.send(:assign_full_path))
      p.send(:sync_child_full_paths!)
    end
  end

  # Escape slug unless it's nonexistent (root)
  def escape_slug
    self.slug = CGI::escape(self.slug) unless self.slug.nil?
  end

  # Unescape the slug and full path back into their original forms unless they're nonexistent
  def unescape_slug_and_path
    self.slug       = CGI::unescape(self.slug)      unless self.slug.nil?
    self.full_path  = CGI::unescape(self.full_path) unless self.full_path.nil?
  end

  private

  def cache_preview
    self.preview_cache = ActionView::Base.full_sanitizer.sanitize(Kramdown::Document.new(block_content).to_html).truncate(100)
  end
end
