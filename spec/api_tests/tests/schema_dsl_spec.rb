require 'test_helper'
require_relative '../loader'

# Exercises the `schema` class DSL (register a named schema), the
# `schema(:name)` reference inside params, the ref/id strip, and the
# central documentation surfaced by Introspect.schema[:schemas].

# Model-like class exposing a Lux::Schema via .schema (mirrors the Sequel
# lux_schema plugin), so the `schema Klass` shortcut can be exercised. The
# `ref?` field proves the pk is stripped on registration.
class DslAccount
  def self.schema
    @schema ||= Lux.schema(:dsl_account) do
      title
      ref? Integer
    end
  end
end

class SchemaDslApi < ApplicationApi
  documented

  # 1. explicit name + inline Lux::Schema
  schema :address, Lux.schema(:dsl_address) { street; city }

  # 2. alias an existing named model schema (registered but not referenced)
  schema :member_user, Lux.schema(:user)

  # 3. lux shortcut: schema DslAccount == schema :dsl_account, DslAccount.schema
  schema DslAccount

  unsafe
  params do
    user    schema(:user)      # falls back to the global :user model schema
    address schema(:address)   # resolves the registered :address ref
  end
  define :create do
    proc { { user: params.user.to_h, address: params.address.to_h } }
  end

  unsafe
  params do
    user Lux.schema(:user)     # inline object form (== `user User.schema`)
  end
  define :create_inline do
    proc { params.user.to_h }
  end

  unsafe
  params do
    user? schema(:user)        # optional object; validated by schema only when provided
  end
  define :create_optional do
    proc { { user: params.user && params.user.to_h } }
  end
end

describe 'schema DSL' do
  describe 'registration' do
    it 'stores explicit name + inline schema in REFS' do
      _(Lux::Schema::REFS['address']).must_be_kind_of Lux::Schema
      _(Lux::Schema::REFS['address'].rules.keys.sort).must_equal %i[city street]
    end

    it 'aliases a named model schema' do
      _(Lux::Schema::REFS['member_user'].rules.keys).must_include :email
    end

    it 'shortcut derives the name from the class and strips the pk (ref)' do
      _(Lux::Schema::REFS['dsl_account']).must_be_kind_of Lux::Schema
      _(Lux::Schema::REFS['dsl_account'].rules.keys).must_equal [:title]   # ref stripped
    end

    it 'rejects a non-schema value' do
      _ { SchemaDslApi.schema(:bad, 'nope') }.must_raise ArgumentError
    end
  end

  describe 'reference + validation' do
    it 'accepts a valid mandatory object' do
      response = SchemaDslApi.render :create,
        params: { user: { name: 'Dux', email: 'd@x.com' }, address: { street: 'S', city: 'C' } }
      _(response[:success]).must_equal true
      _(response[:data][:user]['name']).must_equal 'Dux'
      _(response[:data][:address]['city']).must_equal 'C'
    end

    it 'rejects a bad nested value (email)' do
      response = SchemaDslApi.render :create,
        params: { user: { name: 'Dux', email: 'bad email' }, address: { street: 'S', city: 'C' } }
      _(response[:success]).must_equal false
    end

    it 'inline object form validates the same way' do
      ok  = SchemaDslApi.render :create_inline, params: { user: { name: 'A', email: 'a@b.com' } }
      bad = SchemaDslApi.render :create_inline, params: { user: { name: 'A', email: 'nope' } }
      _(ok[:success]).must_equal true
      _(bad[:success]).must_equal false
    end
  end

  describe 'optional object (user?)' do
    it 'passes when the object is omitted' do
      r = SchemaDslApi.render :create_optional, params: {}
      _(r[:success]).must_equal true
      _(r[:data][:user]).must_be_nil
    end

    it 'filters by schema when the object is provided' do
      r = SchemaDslApi.render :create_optional, params: { user: { name: 'A', email: 'a@b.com' } }
      _(r[:success]).must_equal true
      _(r[:data][:user]['email']).must_equal 'a@b.com'
    end

    it 'rejects an invalid provided object' do
      r = SchemaDslApi.render :create_optional, params: { user: { name: 'A', email: 'nope' } }
      _(r[:success]).must_equal false
    end

    it 'is documented as not required' do
      params = Lux::Api::Introspect.schema[:apis]['schema_dsl'][:collection][:create_optional][:params]
      _(params[:user][:required]).must_equal false
      _(params[:user][:schema]).must_equal 'user'
    end
  end

  describe 'central documentation (Introspect.schema[:schemas])' do
    def doc
      @doc ||= Lux::Api::Introspect.schema
    end

    it 'lists registered and referenced schemas in one place' do
      %w[address member_user dsl_account user].each do |name|
        _(doc[:schemas].key?(name)).must_equal true
      end
    end

    it 'documents schemas without the pk (ref never in schema)' do
      _(doc[:schemas]['dsl_account'].key?(:ref)).must_equal false
    end

    it 'serializes model params as a schema name ref (no raw object)' do
      params = doc[:apis]['schema_dsl'][:collection][:create][:params]
      _(params[:user][:schema]).must_equal 'user'
      _(params[:address][:schema]).must_equal 'address'
      _(params[:user].key?(:model)).must_equal false
    end

    it 'never leaks a Lux::Schema object into the JSON' do
      _(doc.to_json).wont_match(/Lux::Schema/)
    end
  end
end
