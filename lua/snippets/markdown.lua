-- ~/.config/nvim/lua/snippets/markdown.lua
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
    s("daily", fmt([[
---
title: Daily Standup - {}
date: {}
tags: [daily, standup, {}]
---

# Daily Standup - {}

## Team: {}

### What I did yesterday
- {}

### What I'm doing today
- {}

### Blockers / Issues
- {}

### Notes / Discussion
- {}
  ]], {
        i(1, os.date("%Y-%m-%d")), -- title date
        t(os.date("%Y-%m-%d")),    -- frontmatter date
        i(2, "CoverGo"),           -- tag
        rep(1),                    -- title heading
        rep(2),                    -- team name
        i(3), i(4), i(5), i(6)     -- sections
    })),
    -- Note Template
    s("quicknote", {
        t({ "---",
            "title: " }), i(1, "Quick note"), t({ "",
        "date: " }), t(os.date("%Y-%m-%d")), t({ "",
        "tags: [", }), i(2, "tag1, tag2"), t({ "]",
        "---", "",
        "# " }), i(3, "Quick Note"), t({ "",
        "", }), i(0),
    }),
    s("planning", fmt([[
---
title: Sprint Planning - {}
date: {}
tags: [sprint, planning, {}]
---

# Sprint Planning - {}

## Sprint Goal
- {}

## Velocity / Capacity
- Previous Velocity:
- This Sprint Capacity:
- Time Off / Holidays:

## Planned Work (Top Stories)
- [ ] #{} {}
- [ ] #{} {}
- [ ] #{} {}

## Risks / Dependencies
- {}

## Notes
- {}
]], {
        i(1, os.date("%Y-%m-%d")),
        t(os.date("%Y-%m-%d")),
        i(2, "team-name"),
        rep(1),
        i(3, "Sprint goal..."),
        i(4, "123"), i(5, "Story A"),
        i(6, "456"), i(7, "Story B"),
        i(8, "789"), i(9, "Story C"),
        i(10),
        i(11)
    })),
    s("refine", fmt([[
---
title: Backlog Refinement - {}
date: {}
tags: [scrum, refinement, grooming]
---

# Backlog Refinement - {}

## Stories Discussed
- #{} {}
  - [ ] Clarified Acceptance Criteria
  - [ ] Estimated (Story Points: __)
  - [ ] Ready for Sprint

- #{} {}
  - [ ] Needs refinement
  - [ ] Missing dependency details

## Questions / Clarifications
- {}

## Next Steps
- {}
]], {
        i(1, os.date("%Y-%m-%d")),
        t(os.date("%Y-%m-%d")),
        rep(1),
        i(2, "123"), i(3, "Story A"),
        i(4, "456"), i(5, "Story B"),
        i(6),
        i(7)
    })),
    s("review", fmt([[
---
title: Sprint Review - {}
date: {}
tags: [sprint, review, demo]
---

# Sprint Review - {}

## Sprint Goal Recap
- {}

## Delivered Work
- ✅ #{} {}
- ✅ #{} {}
- ❌ #{} {} (reason: {})

## Demo Summary
- {}

## Stakeholder Feedback
- {}

## Action Items
- [ ] {}
- [ ] {}
]], {
        i(1, os.date("%Y-%m-%d")),
        t(os.date("%Y-%m-%d")),
        rep(1),
        i(2),
        i(3, "123"), i(4, "Story A"),
        i(5, "456"), i(6, "Story B"),
        i(7, "789"), i(8, "Story C"), i(9, "reason..."),
        i(10),
        i(11),
        i(12), i(13)
    })),
    s("retro", fmt([[
---
title: Sprint Retrospective - {}
date: {}
tags: [sprint, retro, team]
---

# Sprint Retrospective - {}

## What went well
- {}

## What didn’t go well
- {}

## What can be improved
- {}

## Action Items
- [ ] {}
- [ ] {}

## Health Check (Optional)
- 🔵 Team Happiness: 😊 😐 😞
- 🔵 Process: 👍 👎
]], {
        i(1, os.date("%Y-%m-%d")),
        t(os.date("%Y-%m-%d")),
        rep(1),
        i(2),
        i(3),
        i(4),
        i(5), i(6)
    }))

}
