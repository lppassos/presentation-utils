require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'

require_relative 'extension'

class MermaidThemeFakeDocument
  def initialize(attributes = {})
    @attributes = attributes.transform_keys(&:to_s)
  end

  def attr(name, default = nil)
    @attributes.fetch(name.to_s, default)
  end

  def set_attr(name, value)
    @attributes[name.to_s] = value
  end
end

class MermaidThemeConfigPreprocessorTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir
    @processor = PresentationUtils::MermaidTheme::ThemeConfigPreprocessor.new
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_loads_config_relative_to_theme_file
    config = File.join(@directory, 'mermaid', 'corporate.json')
    FileUtils.mkdir_p(File.dirname(config))
    File.write(config, '{"theme":"base"}')
    File.write(File.join(@directory, 'corporate.yml'), "mermaid:\n  config: mermaid/corporate.json\n")
    document = MermaidThemeFakeDocument.new('pdf-theme' => 'corporate', 'pdf-themesdir' => @directory)

    @processor.process(document, :reader)

    assert_equal config, document.attr('mermaid-config')
  end

  def test_does_not_override_document_mermaid_config
    document = MermaidThemeFakeDocument.new('mermaid-config' => '/document/config.json')

    @processor.process(document, :reader)

    assert_equal '/document/config.json', document.attr('mermaid-config')
  end

  def test_raises_when_theme_config_is_missing
    File.write(File.join(@directory, 'corporate.yml'), "mermaid-config: missing.json\n")
    document = MermaidThemeFakeDocument.new('pdf-theme' => 'corporate', 'pdf-themesdir' => @directory)

    error = assert_raises(RuntimeError) { @processor.process(document, :reader) }

    assert_match(/missing\.json/, error.message)
  end
end
