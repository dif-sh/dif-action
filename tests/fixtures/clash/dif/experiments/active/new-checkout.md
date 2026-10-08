---
id: new-checkout
status: active
owner: dev@example.com
surface: home
hypothesis: >
  Inlining the address form lifts completed checkouts.
variants:
  - id: "off"
    weight: 90
  - id: "on"
    weight: 10
metrics:
  primary: completed_checkout
created: 2026-10-07
---

## Brief

Fixture for the dif-action test workflow.
