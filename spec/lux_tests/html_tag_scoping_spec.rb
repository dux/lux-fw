require 'test_helper'

# Parity tests for HtmlTag scoping rules. Run these BEFORE refactoring to
# pin down current behaviour, then AFTER to prove no regression. Covers:
#   - instance variable copy from host into the builder
#   - method_missing forwarding from builder to @_context (host)
#   - parent / context / this helpers exposing the host explicitly
#   - deeply nested instance_exec - inner blocks still see the host

class ScopingHost
  HtmlTag.mixin(self)

  def initialize
    @greeting = 'hello'
    @count    = 3
  end

  def host_helper
    'helper-value'
  end

  def host_method(suffix)
    "x-#{suffix}"
  end

  # uses @greeting (ivar) and host_helper (method-missing forward)
  def ivar_and_method
    tag.div do
      span @greeting
      em host_helper
    end
  end

  # `this` should expose host explicitly even when shadowed by builder
  def explicit_this
    tag.div do |n|
      n.h1 this.host_method('a')
      n.p  context.host_method('b')
      n.b  parent.host_method('c')
    end
  end

  # deeply nested block - inner block still sees host
  def deep_nesting
    tag.section do
      div do
        ul do
          @count.times do |i|
            li "#{host_method(i)}-#{@greeting}"
          end
        end
      end
    end
  end

  # mixed: kwargs attrs + positional inner + ivar
  def mixed_args
    tag.a @greeting, href: '#', class: 'lead'
  end

  # block ivar mutation should NOT leak back to host
  def ivar_isolation
    out = tag.div do
      @greeting = 'mutated'
      span @greeting
    end
    [out, @greeting]
  end
end

###

describe 'HtmlTag scoping' do
  def host
    @host ||= ScopingHost.new
  end

  it 'copies host @ivars into the builder' do
    _(host.ivar_and_method).must_equal '<div><span>hello</span><em>helper-value</em></div>'
  end

  it 'forwards unknown methods to the host via method_missing' do
    _(host.ivar_and_method).must_include 'helper-value'
  end

  it 'exposes host via this/context/parent' do
    _(host.explicit_this).must_equal '<div><h1>x-a</h1><p>x-b</p><b>x-c</b></div>'
  end

  it 'preserves host scope inside deeply nested blocks' do
    _(host.deep_nesting).must_equal(
      '<section><div><ul><li>x-0-hello</li><li>x-1-hello</li><li>x-2-hello</li></ul></div></section>'
    )
  end

  it 'mixes kwargs attrs + positional inner + ivar' do
    _(host.mixed_args).must_equal '<a href="#" class="lead">hello</a>'
  end

  it 'does not leak builder-local @ivar mutations back to host' do
    out, after = host.ivar_isolation
    _(out).must_equal '<div><span>mutated</span></div>'
    _(after).must_equal 'hello'  # host untouched
  end
end
