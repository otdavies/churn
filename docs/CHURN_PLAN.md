# Churn Plan

## GOAL
Perfect the README.md to production quality - clear, professional, comprehensive without fluff or emojis. Preserve existing flow diagrams. Target audience: developers evaluating or adopting the tool.

## REQUIREMENTS
- Professional tone throughout, no emojis
- Clear value proposition in opening
- Preserve ASCII flow diagrams (they're excellent)
- Concise yet comprehensive - every section earns its place
- Scannable structure with logical hierarchy
- Accurate technical details
- Installation instructions that work
- No marketing fluff or overselling

## TASKS
- [x] Review and tighten opening section - clear value prop in first 2 lines
- [x] Ensure "What It Does" maps accurately to actual features
- [x] Verify install instructions are complete and accurate
- [x] Review Architecture diagram - ensure accuracy
- [x] Tighten Memory Files section - remove redundancy
- [x] Flag Markers section - verify examples are useful
- [x] Churn Workflow section - ensure clear and accurate
- [x] Iteration Cycle diagram - verify matches implementation
- [x] Git Flow section - verify commands match actual behavior
- [x] Build Detection table - verify accuracy
- [x] Commands and Hooks tables - ensure complete and accurate
- [x] Directory Structure - verify matches actual install
- [x] Troubleshooting - add any missing common issues
- [x] Final polish pass - consistency, grammar, formatting

## DONE
- Iteration 1: Rewrote opening section - added 2-sentence value proposition explaining the core problem (context loss at compaction) and solution. Changed "What It Does" to "Features". Made feature bullets more specific about how each feature works.
- Iteration 2 (Review): Verified opening section aligns with plan. Features map correctly to implementation. No drift detected.
- Iteration 3: Fixed install instructions - split jq install onto separate commented line, added explicit clone URL placeholder, documented what gets installed (hooks, commands) and that settings.json is backed up. Verified against install.sh.
- Iteration 4 (Review): Found plan drift - iteration 3 claimed to remove `cd churn` but actually kept it. Added inline comment clarifying that directory name comes from clone. Verified hooks and commands lists match actual files.
- Iteration 5: Verified Architecture diagram accuracy. Checked SESSION LIFECYCLE (4 phases correct), MEMORY LAYERS structure (Global with traces/, Project with shadow-repo/, Branch with working.md). All elements verified against session_start.sh, pre_compact.sh, trace.sh, snapshot.sh. Diagram is accurate - no changes needed.
- Iteration 6 (Review): Comprehensive drift check across all README sections vs implementation. Verified: Build Detection table matches git.sh detect-build exactly, Hooks table "4KB max" claim confirmed (session_start.sh MAX_CONTEXT=4096), Git Flow branch naming matches git.sh format, Directory Structure matches install.sh. No drift found. Remaining tasks properly ordered.
- Iteration 7: Tightened Memory Files section. Table: renamed "Maintained By" to "Updated By", clarified self-model.md update mechanism (manual content, auto session count), made flagged.md purpose clearer ("Flags extracted before compaction"), added "or manual edit" to working.md. Flag Markers: condensed intro from 2 lines to 1, removed redundant closing line about pre_compact.sh (already in intro).
- Iteration 8 (Review): Verified all Iteration 7 changes against implementation. self-model.md session count increment confirmed in pre_compact.sh:54-64. flagged.md extraction confirmed in pre_compact.sh:67-168. working.md updated by save.sh confirmed. Flag Markers intro condensation is accurate. All aligned, no drift.
- Iteration 9: Verified Flag Markers section. All 6 types (prompt, progress, decision, diff, blocker, note) match case statement in pre_compact.sh:104-165. Format `[FLAG:type] content` matches extraction regex on line 93. Example descriptions are accurate and useful. No changes needed.
- Iteration 10 (Final Review): Comprehensive verification complete. All sections verified against implementation:
  - Features: All 3 features map to implementation (memory persistence, iterative refinement, git workflow)
  - Churn Workflow: Commands match churn.md (10, --linear, task modes)
  - Iteration Cycle: Work/Review alternation, validation logic matches churn.md
  - Git Flow: Branch naming (churn/name-MMDD-HHMM) matches git.sh:18
  - Build Detection: All 5 project types match git.sh:71-95
  - Commands: 3 commands (churn, churn-done, churn-push) all exist
  - Hooks: 8 hooks verified, 4KB limit confirmed (session_start.sh:132)
  - Directory Structure: Matches install.sh output
  - Troubleshooting: 4 entries cover common issues
  - No emojis, professional tone throughout
  - README is production quality (212 lines, well-structured)

## NOTES
- Project folder is "pinit" but README says "Churn" - this is the correct name
- Existing diagrams are well-designed ASCII art
- Current README is ~200 lines, well-structured
- Shell scripts are the primary codebase (no standard build)
