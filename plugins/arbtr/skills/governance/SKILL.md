---
name: arbtr-architectural-governance
description: Check Arbtr for architectural decisions before scaffolding features, adding npm dependencies, refactoring code, or making architectural changes, and propose new decisions when you make a significant architectural choice. Use this skill when the user asks to add new features, install libraries, modify system architecture, or restructure code. Requires the Arbtr MCP server to be configured.
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

- **Status**: Is it active, superseded, or archived?
- **Proposal state**: Is it marked **unratified**? That means an agent proposed it and no teammate has accepted it yet.
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

Proceed with your work. If the work makes a significant architectural choice (a library, a pattern, a boundary, a data model, an infrastructure choice), record it (see below).

## Recording Decisions

With a personal agent key configured, you can write to Arbtr. Proposals land in the team's acceptance queue; a teammate accepts, edits, or rejects them.

### Propose a new decision

```
mcp__arbtr__propose_decision
```

- **title**: the decision as a specific noun phrase, 8 to 120 characters. Not "misc updates".
- **context**: at least 200 characters of WHY: the problem, the alternatives you considered, and the reasons for this choice.
- **evidence**: at least one durable artifact: a PR number, commit SHA, file path, URL, or ticket id. Evidence that names only a person is stored but graded **tribal** (a hypothesis, not an instruction).
- **idempotency_key** (optional): a stable key for retries; a replay returns the original proposal.

If the tool refuses with lint errors, fix exactly what the errors say and retry once.

### If a near-duplicate exists

The tool refuses and lists the near matches. Do not retry with `force: true` by default. Instead:

- add what you learned to the existing decision with `mcp__arbtr__add_decision_comment`, or
- if this really is a different decision, retry with `force: true` and say in the context why it is distinct.

If a near match was **rejected** before, the tool says why. Respect that unless the user tells you otherwise.

### Tell the user

After a proposal, tell the user the title and that it is waiting in the acceptance queue. Do not tell them it is "decided".

### Without an agent key

The write tools answer that an agent key is needed. Tell the user they can run `/arbtr:setup`, and continue your work.

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
- **Unratified decisions** (agent proposals not yet accepted) are hypotheses, not constraints - mention them, but don't block on them
- **Your own proposals** are unratified too - do not cite them to the user as team policy
- **Deprecated decisions** have been superseded - check what replaced them
- **When in doubt, search** - It's better to check and find nothing than to miss a relevant decision
