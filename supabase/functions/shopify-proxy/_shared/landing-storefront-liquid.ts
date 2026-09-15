/**
 * App-proxy Liquid document for /apps/loyalty/rewards.
 * Rendered in the shop theme layout (header/footer).
 */
export const LANDING_STOREFRONT_LIQUID = `{% layout 'theme' %}
<div
  class="rocket-landing-block"
  data-rocket-landing-root
  data-audience="{% if customer %}member{% else %}guest{% endif %}"
></div>
<script>
  window.RocketLandingConfig = {
    shop: {{ shop.permanent_domain | json }},
    locale: {{ request.locale.iso_code | json }},
    loginUrl: {{ routes.storefront_login_url | json }},
    customerId: {{ customer.id | json }},
    designMode: false,
    assetBaseUrl: {{ 'landing/hero-bg.png' | asset_url | split: 'hero-bg.png' | first | json }}
  };
</script>
{{ 'landing.css' | asset_url | stylesheet_tag }}
<script src="{{ 'landing.js' | asset_url }}" defer="defer"></script>
`;
