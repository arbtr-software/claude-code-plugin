---
name: arbtr-architectural-governance
description: Check Arbtr for architectural decisions before scaffolding features, adding npm dependencies, refactoring code, or making architectural changes. Use this skill when the user asks to add new features, install libraries, modify system architecture, or restructure code. Requires the Arbtr MCP server to be configured.
---

# Arbtr Architectural Governance

You are working in a codebase governed by **Arbtr** - the System of Record for Decisions. Before making significant changes, you MUST check for existing architectural decisions that may affect your approach.

## When to Check Arbtr

Before performing ANY of these actions, you MUST search Arbtr for relevant decisions:

1. **Scaffolding new features** - Check for decisions about patterns, frameworks, or approaches
2. **Adding npm dependencies** - Check for decisions about approved/prohibited libraries
3. **Refactoring code** - Check for decisions about architectural boundaries or patterns
4. **Modifying APIs** - Check for decisions about API design, versioning, or contracts
5. **Changing data models** - Check for decisions about database schema or data patterns
6. **Infrastructure changes** - Check for decisions about deployment, hosting, or services

## How to Check Arbtr

Use the Arbtr MCP server tools in this order:

### Step 1: Search for Relevant Decisions

```
mcp__arbtr__search_decisions
```

Search with keywords related to your task. For example:

- Adding a date library? Search: "date library", "moment", "dayjs", "date-fns"
- Adding authentication? Search: "auth", "authentication", "login", "session"
- Refactoring components? Search: "component", "architecture", "patterns"

### Step 2: Review Decision Details

If you find relevant decisions, get the full details:

```
mcp__arbtr__get_decision
```

Read the decision's:

- **Status**: Is it `accepted`, `proposed`, or `deprecated`?
- **Context**: What problem was being solved?
- **Conclusion**: What was decided?
- **Arguments**: What trade-offs were considered?

## How to Handle Conflicts

### If your proposed change CONFLICTS with an existing decision:

1. **STOP** - Do not proceed with the conflicting approach
2. **WARN the user** - Clearly explain:
   - What decision exists
   - How their request conflicts with it
   - What the approved approach is
3. **Offer alternatives**:
   - Modify your approach to comply with the decision
   - Ask if they want to propose superseding the decision in Arbtr

Example response:

```
I found an existing architectural decision that affects this request:

**Decision: "Use date-fns for Date Handling"** (Status: Accepted)
- This decision prohibits adding moment.js due to bundle size concerns
- The approved library is date-fns

I can either:
1. Implement this using date-fns instead (recommended)
2. Help you create a proposal in Arbtr to supersede this decision

Which would you prefer?
```

### If NO relevant decisions exist:

Proceed with your work, but consider:

- Should this architectural choice be recorded as a new decision?
- Mention to the user: "I didn't find any existing decisions about [topic]. Consider recording this choice in Arbtr if it's significant."

## Example Workflow

**User**: "Add moment.js to handle date formatting in the dashboard"

**Your process**:

1. Search Arbtr: `search_decisions` with query "date library moment formatting"
2. Find decision: "Use date-fns for Date Handling" (Accepted)
3. Read decision details: Prohibits moment.js, requires date-fns
4. Respond to user with the conflict and alternatives
5. If user agrees, implement with date-fns instead

**User**: "Refactor the API layer to use GraphQL"

**Your process**:

1. Search Arbtr: `search_decisions` with query "API GraphQL REST architecture"
2. Find decision: "REST-first API Design" (Accepted)
3. Read decision details: Team committed to REST for simplicity
4. Warn user about conflict, offer to help propose superseding decision
5. If user wants to proceed anyway, help them create a proper proposal in Arbtr

## Important Notes

- **Always check Arbtr first** - Never skip this step for significant changes
- **Respect accepted decisions** - They represent team consensus
- **Proposed decisions** are still under discussion - warn but don't block
- **Deprecated decisions** have been superseded - check what replaced them
- **When in doubt, search** - It's better to check and find nothing than to miss a relevant decision
