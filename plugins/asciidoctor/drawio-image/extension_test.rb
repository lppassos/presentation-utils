require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'

# Load the extension without triggering the global Asciidoctor registration
# (we require it after stubbing so the constant is available).
require_relative 'extension'

# ---------------------------------------------------------------------------
# Minimal document double that mimics the subset of the Asciidoctor::Document
# API used by DrawioImageProcessor.
# ---------------------------------------------------------------------------
class FakeDoc
  def initialize(attrs = {})
    @attrs = attrs
  end

  def attr(name, default = nil)
    @attrs.fetch(name.to_s, default)
  end

  # Mimic find_by so the processor can walk nodes.
  def find_by(context:)
    (@nodes ||= []).select { |n| n.context == context }
  end

  def add_node(node)
    (@nodes ||= []) << node
    self
  end
end

# ---------------------------------------------------------------------------
# Minimal image-node double.
# ---------------------------------------------------------------------------
class FakeImageNode
  attr_reader :context

  def initialize(target, context = :image)
    @attrs   = { 'target' => target }
    @context = context
  end

  def attr(name, _default = nil)
    @attrs[name.to_s]
  end

  def set_attr(name, value)
    @attrs[name.to_s] = value
  end
end

# ---------------------------------------------------------------------------
# Helper to get a bare processor instance (bypasses DSL registration).
# ---------------------------------------------------------------------------
def new_processor
  PresentationUtils::DrawioImage::DrawioImageProcessor.new
end

# ---------------------------------------------------------------------------
# Platform-neutral helpers
# ---------------------------------------------------------------------------

# Build an absolute path string using the OS separator, so assertions work on
# both Unix (/docs/arch.drawio) and Windows (C:/docs/arch.drawio).
def abs(*parts)
  # File.expand_path with an absolute-looking base produces the right result
  # on all platforms when the base itself is already absolute.
  File.join(File.expand_path(parts.first), *parts[1..])
end

# ===========================================================================
# Tests
# ===========================================================================

class TestResolveDrawioPath < Minitest::Test
  def setup
    @proc = new_processor
    @dir  = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_no_imagesdir_falls_back_to_docdir
    doc = FakeDoc.new('docdir' => @dir, 'imagesdir' => '')
    expected = File.join(@dir, 'arch.drawio')
    assert_equal expected, @proc.send(:resolve_drawio_path, doc, 'arch.drawio')
  end

  def test_relative_imagesdir_expanded_relative_to_docdir
    doc = FakeDoc.new('docdir' => @dir, 'imagesdir' => 'images')
    expected = File.join(@dir, 'images', 'arch.drawio')
    assert_equal expected, @proc.send(:resolve_drawio_path, doc, 'arch.drawio')
  end

  def test_absolute_imagesdir_used_as_is
    abs_images = File.join(@dir, 'assets', 'images')
    doc = FakeDoc.new('docdir' => @dir, 'imagesdir' => abs_images)
    expected = File.join(abs_images, 'arch.drawio')
    assert_equal expected, @proc.send(:resolve_drawio_path, doc, 'arch.drawio')
  end

  def test_missing_imagesdir_key_falls_back_to_docdir
    doc = FakeDoc.new('docdir' => @dir)
    expected = File.join(@dir, 'flow.drawio')
    assert_equal expected, @proc.send(:resolve_drawio_path, doc, 'flow.drawio')
  end
end

class TestPngOutputPath < Minitest::Test
  def setup
    @proc = new_processor
    @dir  = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_uses_imagesoutdir_when_set
    outdir = File.join(@dir, '.imggen')
    doc    = FakeDoc.new('docdir' => @dir, 'imagesdir' => 'images', 'imagesoutdir' => '.imggen')
    result = @proc.send(:png_output_path, doc, 'arch.drawio')
    assert_equal File.join(outdir, 'arch.png'), result
  end

  def test_falls_back_to_imagesdir_when_imagesoutdir_absent
    imagesdir = File.join(@dir, 'images')
    doc = FakeDoc.new('docdir' => @dir, 'imagesdir' => 'images')
    result = @proc.send(:png_output_path, doc, 'arch.drawio')
    assert_equal File.join(imagesdir, 'arch.png'), result
  end

  def test_falls_back_to_docdir_when_both_absent
    doc = FakeDoc.new('docdir' => @dir)
    result = @proc.send(:png_output_path, doc, 'arch.drawio')
    assert_equal File.join(@dir, 'arch.png'), result
  end

  def test_absolute_imagesoutdir_used_as_is
    abs_out = File.join(@dir, 'out')
    doc = FakeDoc.new('docdir' => @dir, 'imagesoutdir' => abs_out)
    result = @proc.send(:png_output_path, doc, 'arch.drawio')
    assert_equal File.join(abs_out, 'arch.png'), result
  end

  def test_basename_only_no_subdirectory_nesting
    abs_out = File.join(@dir, 'out')
    doc = FakeDoc.new('docdir' => @dir, 'imagesoutdir' => abs_out)
    result = @proc.send(:png_output_path, doc, 'sub/dir/arch.drawio')
    assert_equal File.join(abs_out, 'arch.png'), result
  end
end

class TestConversionNeeded < Minitest::Test
  def setup
    @proc = new_processor
    @dir  = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_true_when_png_absent
    drawio = File.join(@dir, 'a.drawio')
    png    = File.join(@dir, 'a.png')
    FileUtils.touch(drawio)
    assert @proc.send(:conversion_needed?, drawio, png)
  end

  def test_true_when_drawio_is_newer_than_png
    drawio = File.join(@dir, 'a.drawio')
    png    = File.join(@dir, 'a.png')
    FileUtils.touch(drawio)
    FileUtils.touch(png)
    past   = Time.now - 10
    future = Time.now + 10
    File.utime(past, past, png)
    File.utime(future, future, drawio)
    assert @proc.send(:conversion_needed?, drawio, png)
  end

  def test_false_when_png_is_newer_than_drawio
    drawio = File.join(@dir, 'a.drawio')
    png    = File.join(@dir, 'a.png')
    FileUtils.touch(drawio)
    FileUtils.touch(png)
    past   = Time.now - 10
    recent = Time.now + 10
    File.utime(past, past, drawio)
    File.utime(recent, recent, png)
    refute @proc.send(:conversion_needed?, drawio, png)
  end
end

class TestConvertToPng < Minitest::Test
  def setup
    @proc = new_processor
    @dir  = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_raises_on_non_zero_exit
    drawio = File.join(@dir, 'a.drawio')
    png    = File.join(@dir, 'a.png')
    FileUtils.touch(drawio)

    # Stub Open3.capture2e to simulate a failing drawio run
    fake_status = Minitest::Mock.new
    fake_status.expect(:success?, false)
    fake_status.expect(:exitstatus, 1)

    Open3.stub(:capture2e, ['conversion error output', fake_status]) do
      err = assert_raises(RuntimeError) { @proc.send(:convert_to_png, drawio, png) }
      assert_match(/drawio export failed/, err.message)
      assert_match(/exit 1/, err.message)
    end

    fake_status.verify
  end

  def test_succeeds_and_creates_output_dir
    drawio  = File.join(@dir, 'a.drawio')
    outdir  = File.join(@dir, 'sub', 'out')
    png     = File.join(outdir, 'a.png')
    FileUtils.touch(drawio)

    fake_status = Minitest::Mock.new
    fake_status.expect(:success?, true)

    Open3.stub(:capture2e, ['', fake_status]) do
      @proc.send(:convert_to_png, drawio, png)
    end

    assert Dir.exist?(outdir), 'output directory should have been created'
    fake_status.verify
  end

  def test_correct_command_assembled
    drawio = File.join(@dir, 'a.drawio')
    png    = File.join(@dir, 'a.png')
    FileUtils.touch(drawio)

    captured_cmd = nil
    fake_status  = Minitest::Mock.new
    fake_status.expect(:success?, true)

    Open3.stub(:capture2e, lambda { |*args|
      captured_cmd = args
      ['', fake_status]
    }) do
      @proc.send(:convert_to_png, drawio, png)
    end

    assert_equal ['xvfb-run', '-a', 'drawio', '--no-sandbox', '-x', '-f', 'png', '-o', png, drawio], captured_cmd
    fake_status.verify
  end
end

class TestProcess < Minitest::Test
  def setup
    @proc = new_processor
    @dir  = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_rewrites_drawio_target_to_png
    drawio_file = File.join(@dir, 'arch.drawio')
    png_file    = File.join(@dir, 'arch.png')
    FileUtils.touch(drawio_file)

    doc  = FakeDoc.new('docdir' => @dir, 'imagesdir' => '', 'imagesoutdir' => '')
    node = FakeImageNode.new('arch.drawio')
    doc.add_node(node)

    fake_status = Minitest::Mock.new
    fake_status.expect(:success?, true)

    Open3.stub(:capture2e, ['', fake_status]) do
      @proc.process(doc)
    end

    assert_equal png_file, node.attr('target')
    fake_status.verify
  end

  def test_leaves_non_drawio_target_unchanged
    doc  = FakeDoc.new('docdir' => @dir)
    node = FakeImageNode.new('photo.png')
    doc.add_node(node)

    @proc.process(doc)

    assert_equal 'photo.png', node.attr('target')
  end

  def test_skips_rewrite_when_conversion_fails
    drawio_file = File.join(@dir, 'bad.drawio')
    FileUtils.touch(drawio_file)

    doc  = FakeDoc.new('docdir' => @dir, 'imagesdir' => '', 'imagesoutdir' => '')
    node = FakeImageNode.new('bad.drawio')
    doc.add_node(node)

    fake_status = Minitest::Mock.new
    fake_status.expect(:success?, false)
    fake_status.expect(:exitstatus, 2)

    Open3.stub(:capture2e, ['error', fake_status]) do
      @proc.process(doc) # must not raise
    end

    # target should remain unchanged since conversion failed
    assert_equal 'bad.drawio', node.attr('target')
    fake_status.verify
  end

  def test_inline_image_nodes_are_also_processed
    drawio_file = File.join(@dir, 'inline.drawio')
    png_file    = File.join(@dir, 'inline.png')
    FileUtils.touch(drawio_file)

    doc  = FakeDoc.new('docdir' => @dir, 'imagesdir' => '', 'imagesoutdir' => '')
    node = FakeImageNode.new('inline.drawio', :inline_image)
    doc.add_node(node)

    fake_status = Minitest::Mock.new
    fake_status.expect(:success?, true)

    Open3.stub(:capture2e, ['', fake_status]) do
      @proc.process(doc)
    end

    assert_equal png_file, node.attr('target')
    fake_status.verify
  end
end
