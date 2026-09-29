# Founder review — round 5 (2026-09-30)

for SAP I think we need to assume pulling product master data too? and Posting major domains of activities e.g. transactions, points, redemptions. why did we put none?

For POS mention that depend on method in table. and defer to the pos integration section. for integration they POST us no charge. Us create middleware to GET data from them end of day yes charge. Read order files from email no charge. Manual upload obviously no charge. In the POS section, we need to mention that there are many types of POS integration depending on the requirements and readiness of POS for integration, but our methods can cover all scenarios.

For the diagram in the first image [§03 third-party → own-channel flow], I prefer if it is from left to right rather than top to bottom. For these diagrams, they all have some gray background, but can we just not put the gray background? Just put the diagrams directly on the white page background.

For the second image [§08 AI analysis admin embed], can we ensure that it scrolls to the top of the screen for that iframe?

For data lake, are you sure the event stream we already have doesn't feel familiar? Should we remove it?

I think we need a section on high-level architecture and security. Can we pull information from the samitivej?

For the executive summary diagram where we show the objective, current state, future state, and impact, see the third image reference [Samitivej objectives grid: Objectives | Current State ▶ Future State | Business Impact with ▲▼]. Can we create something like this in code?
