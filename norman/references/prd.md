# Mode 1: PRD (Requirements Generation)

Start with: "norman prd", "create a prd", "write prd for", "plan this feature", "requirements for", "spec out"

### Step 1: Clarifying Questions

Ask 3-5 critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

Format with lettered options so users can respond quickly (e.g. "1A, 2C, 3B"):

```
1. What is the primary goal?
   A. Option one
   B. Option two
   C. Other: [please specify]
```

### Step 2: Generate PRD

Generate the PRD with these sections:

#### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

#### 2. Goals
Specific, measurable objectives (bullet list).

#### 3. User Stories
Each story should be small enough to implement in one focused session.

```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Given [precondition], when [action], then [observable outcome]
- [ ] Or: [concrete input/state] produces [concrete output/state]
```

**Important:** Each criterion must be directly translatable into a test assertion — concrete enough that the worker can write a failing test for it *before* writing any implementation code (see tests-first directive in Mode 4, Step 5 — `continue.md`).

- Bad: "Works correctly", "Handles errors gracefully", "Performs well"
- OK: "Button shows confirmation dialog before deleting"
- Good: "Clicking Delete on a record with id=42 opens a modal containing the text 'Delete record 42?' with Confirm and Cancel buttons"
- Good: "POST /users with `{email: 'x@y.com', age: -1}` returns 400 with body `{error: 'age must be >= 0'}`"

When in doubt, ask yourself: "Could a junior developer read this and write a passing test without further clarification?" If not, make it more concrete.

#### 4. Functional Requirements
Numbered list: "FR-1: The system must..."

#### 5. Non-Goals (Out of Scope)
What this feature will NOT include.

#### 6. Technical Considerations (Optional)
Known constraints, dependencies, integration points, performance requirements.

#### 7. Success Metrics
How will success be measured?

#### 8. Open Questions
Remaining questions or areas needing clarification.

### Step 3: Save

- Save to `prds/research/prd-[feature-name].md` (kebab-case)
- Create `prds/` directory structure if it doesn't exist
- Do NOT add to TASKS.md yet (that happens during import)
- Tell the user: "PRD saved to research/. Run `norman import` when ready to extract tasks."

### Writing Style

The PRD reader may be a junior developer or AI agent. Therefore:
- Be explicit and unambiguous
- Avoid jargon or explain it
- Number requirements for easy reference
- Use concrete examples where helpful

