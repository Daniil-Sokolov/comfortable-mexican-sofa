# encoding: utf-8

class Cms::PageContent < ActiveRecord::Base
  
  ComfortableMexicanSofa.establish_connection(self)
  
  self.table_name = 'cms_page_contents'
  
  attr_accessor :tags
  
  # -- Relationships --------------------------------------------------------
  belongs_to :page
  
  has_many :blocks,
    :autosave   => true,
    :dependent  => :destroy
    
  # -- Callbacks ------------------------------------------------------------
  before_validation :assigns_label,
                    :escape_slug,
                    :assign_full_path
  after_save        :sync_child_pages
  after_find        :unescape_slug_and_path
  
  # -- Validations ----------------------------------------------------------
  validates :label,
    :presence   => true
  validates :slug,
    :presence   => true,
    :uniqueness => { :scope => :parent_id },
    :unless     => lambda{ |p| p.site && (p.site.pages.count == 0 || p.site.pages.root == self) }
  validate :validate_format_of_unescaped_slug
  
  # -- Instance Methods -----------------------------------------------------
  # Transforms existing cms_block information into a hash that can be used
  # during form processing. That's the only way to modify cms_blocks.
  def blocks_attributes(was = false)
    self.blocks.collect do |block|
      block_attr = {}
      block_attr[:identifier] = block.identifier
      block_attr[:content]    = was ? block.content_was : block.content
      block_attr
    end
  end
  
  # Array of block hashes in the following format:
  #   [
  #     { :identifier => 'block_1', :content => 'block content' },
  #     { :identifier => 'block_2', :content => 'block content' }
  #   ]
  def blocks_attributes=(block_hashes = [])
    block_hashes = block_hashes.values if block_hashes.is_a?(Hash)
    block_hashes.each do |block_hash|
      block_hash.symbolize_keys! unless block_hash.is_a?(HashWithIndifferentAccess)
      block = 
        self.blocks.detect{|b| b.identifier == block_hash[:identifier]} || 
        self.blocks.build(:identifier => block_hash[:identifier])
      block.content = block_hash[:content]
      self.blocks_attributes_changed = self.blocks_attributes_changed || block.content_changed?
    end
  end
  
  # Processing content will return rendered content and will populate 
  # self.cms_tags with instances of CmsTag
  def content(force_reload = false)
    @content = force_reload ? nil : read_attribute(:content)
    @content ||= begin
      self.tags = [] # resetting
      if page.layout
        ComfortableMexicanSofa::Tag.process_content(
          self,
          ComfortableMexicanSofa::Tag.sanitize_irb(page.layout.merged_content)
        )
      else
        ''
      end
    end
  end
  
  # Array of cms_tags for a page. Content generation is called if forced.
  # These also include initialized cms_blocks if present
  def tags(force_reload = false)
    self.content(true) if force_reload
    @tags ||= []
  end
  
  # Full url for a page
  def url
    "http://" + "#{self.site.hostname}/#{self.site.path}/#{self.full_path}".squeeze("/")
  end
  
  # Method to collect prevous state of blocks for revisions
  def blocks_attributes_was
    blocks_attributes(true)
  end
  
protected
  
  def assigns_label
    self.label = self.label.blank?? self.slug.try(:titleize) : self.label
  end
  
  # Escape slug unless it's nonexistent (root)
  def escape_slug
    self.slug = CGI::escape(self.slug) unless self.slug.nil?
  end
  
  def assign_full_path
    self.full_path = self.parent ? "#{CGI::escape(self.parent.full_path).gsub('%2F', '/')}/#{self.slug}".squeeze('/') : '/'
  end
  
  # NOTE: This can create 'phantom' page blocks as they are defined in the layout. This is normal.
  def set_cached_content
    write_attribute(:content, self.content(true))
  end
  
  # Forcing re-saves for child pages so they can update full_paths
  def sync_child_pages
    children.each{ |p| p.save! } if full_path_changed?
  end
  
  # Unescape the slug and full path back into their original forms unless they're nonexistent
  def unescape_slug_and_path
    self.slug       = CGI::unescape(self.slug)      unless self.slug.nil?
    self.full_path  = CGI::unescape(self.full_path) unless self.full_path.nil?
  end
  
  def validate_format_of_unescaped_slug
    return unless slug.present?
    unescaped_slug = CGI::unescape(self.slug)
    errors.add(:slug, :invalid) unless unescaped_slug =~ /^\p{Alnum}[\.\p{Alnum}\p{Mark}_-]*$/i
  end
  
end