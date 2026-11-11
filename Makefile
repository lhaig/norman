REPO        := $(CURDIR)
CLAUDE_HOME := $(HOME)/.claude
SKILLS      := $(CLAUDE_HOME)/skills
CODEX_HOME  := $(HOME)/.codex
CODEX_SKILLS := $(HOME)/.agents/skills
BACKUP      := $(CLAUDE_HOME)/.repo-sync-backup-$(shell date +%Y%m%d-%H%M%S)

# Claude Code: skills, the agent library, and the statusline are all symlinks.
LINKS := \
	$(SKILLS)/norman:$(REPO)/norman \
	$(SKILLS)/prd:$(REPO)/prd \
	$(SKILLS)/sweep:$(REPO)/sweep \
	$(CLAUDE_HOME)/statusline.sh:$(REPO)/statusline/statusline.sh

# The agent library is linked as a whole directory by default. To install a
# subset, list the agent names to leave out (one per line, '#' comments allowed)
# in AGENTS_EXCLUDE_FILE. ~/.claude/agents then becomes a real directory holding
# one symlink per installed agent, and the Codex install skips the same names.
# Every agent stays in this repo either way.
AGENTS_LINK         := $(CLAUDE_HOME)/agents:$(REPO)/agents
AGENTS_EXCLUDE_FILE ?= $(CLAUDE_HOME)/norman-agents-exclude
AGENTS_EXCLUDE      := $(strip $(shell [ -f "$(AGENTS_EXCLUDE_FILE)" ] && sed -e 's/\#.*//' "$(AGENTS_EXCLUDE_FILE)" | tr -s ' \t\n' ' '))

# Codex: skills are symlinked (Codex follows skill directory links); agents are
# generated into ~/.codex/agents/ as TOML by tools/codex-agents, since Codex
# does not read the markdown format. The global instructions file is shared
# with Claude Code: Codex reads ~/.codex/AGENTS.md where Claude reads
# ~/.claude/CLAUDE.md, and the content is the same set of rules.
CODEX_LINKS := \
	$(CODEX_SKILLS)/norman:$(REPO)/norman \
	$(CODEX_SKILLS)/prd:$(REPO)/prd \
	$(CODEX_SKILLS)/sweep:$(REPO)/sweep \
	$(CODEX_HOME)/AGENTS.md:$(CLAUDE_HOME)/CLAUDE.md

.PHONY: install uninstall status install-codex uninstall-codex status-codex test help

help:
	@echo "Claude Code targets:"
	@echo "  install          Symlink skills/agents/statusline from this repo into ~/.claude/"
	@echo "                   (agents named in $(AGENTS_EXCLUDE_FILE) are left out)"
	@echo "                   (backs up existing real files/dirs to a timestamped folder)"
	@echo "  uninstall        Remove symlinks that point into this repo (leaves backups)"
	@echo "  status           Show current link state of each managed path"
	@echo "Codex targets:"
	@echo "  install-codex    Symlink skills into ~/.agents/skills/ and generate ~/.codex/agents/*.toml"
	@echo "  uninstall-codex  Remove the skill symlinks and generated agent TOML files"
	@echo "  status-codex     Show link state and generated agent count"
	@echo "Other:"
	@echo "  test             Run the Go tests for tools/"

# $(call link-pairs,<dest:src pairs>)
define link-pairs
	for pair in $(1); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		mkdir -p "$$(dirname "$$dest")"; \
		if [ -L "$$dest" ]; then \
			if [ "$$(readlink "$$dest")" = "$$src" ]; then \
				echo "[skip] $$dest -> already linked"; \
				continue; \
			fi; \
			echo "[relink] $$dest -> $$src"; \
			rm "$$dest"; \
		elif [ -e "$$dest" ]; then \
			mkdir -p "$(BACKUP)"; \
			echo "[backup] $$dest -> $(BACKUP)/"; \
			mv "$$dest" "$(BACKUP)/" || exit 1; \
			echo "[link]   $$dest -> $$src"; \
		else \
			echo "[link]   $$dest -> $$src"; \
		fi; \
		ln -s "$$src" "$$dest" || exit 1; \
	done
endef

# $(call unlink-pairs,<dest:src pairs>)
define unlink-pairs
	for pair in $(1); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		if [ -L "$$dest" ] && [ "$$(readlink "$$dest")" = "$$src" ]; then \
			rm "$$dest"; echo "[unlink] $$dest"; \
		else \
			echo "[skip]   $$dest (not a symlink into this repo)"; \
		fi; \
	done
endef

# $(call status-pairs,<dest:src pairs>)
define status-pairs
	for pair in $(1); do \
		dest=$${pair%%:*}; src=$${pair##*:}; \
		if [ -L "$$dest" ]; then \
			target=$$(readlink "$$dest"); \
			if [ "$$target" = "$$src" ]; then \
				echo "[ok]   $$dest -> $$target"; \
			else \
				echo "[warn] $$dest -> $$target (expected $$src)"; \
			fi; \
		elif [ -e "$$dest" ]; then \
			echo "[real] $$dest (not a symlink)"; \
		else \
			echo "[miss] $$dest"; \
		fi; \
	done
endef

# Per-agent links, used when AGENTS_EXCLUDE is set. Replaces a whole-directory
# link, drops links for excluded or deleted agents, and never touches a real file.
define link-agent-files
	dest="$(CLAUDE_HOME)/agents"; src="$(REPO)/agents"; excl=" $(AGENTS_EXCLUDE) "; \
	for n in $(AGENTS_EXCLUDE); do \
		[ -f "$$src/$$n.md" ] || echo "[warn] $(AGENTS_EXCLUDE_FILE) names '$$n', which is not an agent in this repo"; \
	done; \
	if [ -L "$$dest" ]; then \
		if [ "$$(readlink "$$dest")" = "$$src" ]; then \
			unlink "$$dest"; echo "[unlink] $$dest (whole-directory link, replaced by per-agent links)"; \
		else \
			echo "[error] $$dest is a symlink to $$(readlink "$$dest"), not this repo; leaving it alone"; exit 1; \
		fi; \
	fi; \
	mkdir -p "$$dest"; \
	for l in "$$dest"/*.md; do \
		[ -L "$$l" ] || continue; \
		t=$$(readlink "$$l"); n=$$(basename "$$l" .md); \
		case "$$t" in "$$src"/*) ;; *) continue ;; esac; \
		if [ ! -e "$$t" ]; then unlink "$$l"; echo "[drop]   $$n (no longer in the repo)"; continue; fi; \
		case "$$excl" in *" $$n "*) unlink "$$l"; echo "[drop]   $$n (excluded)" ;; esac; \
	done; \
	count=0; \
	for f in "$$src"/*.md; do \
		n=$$(basename "$$f" .md); \
		[ "$$n" = "README" ] && continue; \
		case "$$excl" in *" $$n "*) continue ;; esac; \
		l="$$dest/$$n.md"; count=$$((count + 1)); \
		if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$$f" ]; then continue; fi; \
		if [ -e "$$l" ] && [ ! -L "$$l" ]; then echo "[keep]   $$l is a real file, not replaced"; continue; fi; \
		ln -sfn "$$f" "$$l" || exit 1; echo "[link]   $$l"; \
	done; \
	echo "[agents] $$count installed, $(words $(AGENTS_EXCLUDE)) excluded"
endef

# Remove per-agent links that point into this repo; remove the directory if that empties it.
define unlink-agent-files
	dest="$(CLAUDE_HOME)/agents"; src="$(REPO)/agents"; \
	if [ -d "$$dest" ] && [ ! -L "$$dest" ]; then \
		for l in "$$dest"/*.md; do \
			[ -L "$$l" ] || continue; \
			case "$$(readlink "$$l")" in "$$src"/*) unlink "$$l" ;; esac; \
		done; \
		rmdir "$$dest" 2>/dev/null && echo "[unlink] $$dest (per-agent links)" || echo "[keep]   $$dest still holds files that are not from this repo"; \
	fi
endef

install:
	@$(call link-pairs,$(LINKS))
ifeq ($(AGENTS_EXCLUDE),)
	@$(call unlink-agent-files)
	@$(call link-pairs,$(AGENTS_LINK))
else
	@$(call link-agent-files)
endif
	@echo "Done. Run 'make status' to verify."

uninstall:
	@$(call unlink-pairs,$(LINKS))
	@$(call unlink-agent-files)
	@$(call unlink-pairs,$(AGENTS_LINK))

status:
	@$(call status-pairs,$(LINKS))
ifeq ($(AGENTS_EXCLUDE),)
	@$(call status-pairs,$(AGENTS_LINK))
else
	@n=0; for l in "$(CLAUDE_HOME)"/agents/*.md; do \
			[ -L "$$l" ] || continue; \
			case "$$(readlink "$$l")" in "$(REPO)/agents"/*) n=$$((n + 1)) ;; esac; \
		done; \
		echo "[info] $$n agents linked in $(CLAUDE_HOME)/agents/, $(words $(AGENTS_EXCLUDE)) excluded by $(AGENTS_EXCLUDE_FILE)"
endif

install-codex:
	@$(call link-pairs,$(CODEX_LINKS))
	@cd tools/codex-agents && go run . -src "$(REPO)/agents" -out "$(CODEX_HOME)/agents"
	@for n in $(AGENTS_EXCLUDE); do \
		f="$(CODEX_HOME)/agents/$$n.toml"; \
		if [ -f "$$f" ] && grep -q '^# generated by norman' "$$f"; then unlink "$$f"; echo "[drop]   $$n (excluded)"; fi; \
	done
	@echo "Done. Run 'make status-codex' to verify."

uninstall-codex:
	@$(call unlink-pairs,$(CODEX_LINKS))
	@cd tools/codex-agents && go run . -out "$(CODEX_HOME)/agents" -uninstall

status-codex:
	@$(call status-pairs,$(CODEX_LINKS))
	@n=$$(grep -ls '^# generated by norman' "$(CODEX_HOME)"/agents/*.toml 2>/dev/null | wc -l); \
		echo "[info] $$n generated agents in $(CODEX_HOME)/agents/"

test:
	@cd tools/codex-agents && go test ./...
