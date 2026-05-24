module Lux
  module Test
    # Custom assertions mixed into Minitest::Spec. Kept to a small,
    # documented set so AI-written tests can't reach for invented matchers.
    # All take a Lux::Response (or anything that responds to the same names).
    module Assertions
      # assert_status 200, response
      def assert_status code, resp
        actual = resp.respond_to?(:status) ? resp.status.to_i : resp.to_i
        assert_equal code, actual, 'Expected status %d, got %d. Body: %s' % [code, actual, _resp_body_preview(resp)]
      end

      # assert_redirect '/login', response
      def assert_redirect path, resp
        actual = resp.respond_to?(:redirect_to) ? resp.redirect_to : nil
        assert_equal path, actual
      end

      # assert_body_includes 'Hello', response
      def assert_body_includes substr, resp
        body = resp.respond_to?(:body) ? resp.body : resp.to_s
        assert_includes body.to_s, substr
      end

      # assert_json_includes({ ok: true }, response)
      # Subset match: every key in `subset` must equal the same key in the
      # parsed JSON body. Works on any object that responds to #json.
      def assert_json_includes subset, resp
        json = resp.respond_to?(:json) ? resp.json : resp
        subset.each do |k, v|
          actual = json[k] || json[k.to_s]
          assert_equal v, actual, 'JSON key %p mismatch (full body: %p)' % [k, json]
        end
      end

      private

      def _resp_body_preview resp
        body = resp.respond_to?(:body) ? resp.body : resp
        body.to_s[0, 200]
      end
    end
  end
end
