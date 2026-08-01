# Источники и принципы

Проверено 2026-08-01. Workflow намеренно объединяет практики разных инструментов,
а не требует конкретного coding agent.

## Постоянные инструкции

- [AGENTS.md open format](https://agents.md/) — предсказуемый repo-level файл
  инструкций для coding agents.
- [OpenAI: Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
  — Codex читает корневой и вложенные `AGENTS.md`; короткие repo-wide правила
  стоит держать в корне, подробности можно выносить в связанные документы.
- [OpenAI Codex best practices](https://learn.chatgpt.com/guides/best-practices)
  — goal/context/constraints/done-when, plan-first для сложной работы, reusable
  guidance и обязательная validation/review петля.

## Small batches и plan-first

- [GitHub: best practices for Copilot coding agent](https://docs.github.com/en/copilot/tutorials/cloud-agent/get-the-best-results)
  — well-scoped tasks, явные acceptance criteria, repository research и plan до
  реализации; сложную domain/security/business logic не следует бездумно
  делегировать.
- [DORA: Balancing AI tensions](https://dora.dev/insights/balancing-ai-tensions/)
  — small batches названы ключевой защитой от рисков AI-assisted development.
- [Harper Reed: My LLM codegen workflow](https://harper.blog/2025/02/16/my-llm-codegen-workflow-atm/)
  — spec → plan → маленькие iterative/TDD chunks, сохраняемые как task state.
- [Addy Osmani: My LLM coding workflow](https://addyosmani.com/blog/ai-coding-workflow/)
  — маленькие циклы и коммиты, тест после каждого изменения, git history как
  журнал понимания и средство bisect.

## Evidence, simplicity и cognitive debt

- [Simon Willison: Your job is to deliver code you have proven to work](https://simonwillison.net/2025/Dec/18/code-proven-to-work/)
  — manual demonstration плюс automated test; агент должен предоставить evidence,
  а не переносить всю проверку на человека без подготовленных доказательств.
- [Armin Ronacher: Agentic Coding Recommendations](https://lucumr.pocoo.org/2025/6/12/agentic-coding/)
  — простой код, быстрые инструменты, явные логи и observability снижают сложность
  работы и агента, и человека.
- [Margaret-Anne Storey: Cognitive Debt](https://margaretstorey.com/blog/2026/02/09/cognitive-debt/)
  — скорость без сохранённой человеческой модели системы создаёт долг понимания;
  требуется человек, понимающий каждое shipped AI-change, intent documentation и
  регулярные checkpoints.
- [DORA 2025: State of AI-assisted Software Development](https://dora.dev/research/2025/dora-report/)
  — AI усиливает как сильные, так и слабые стороны существующего delivery system.

## Что является локальной эвристикой

Лимиты 50/300/600 LOC и 5 production-файлов не взяты из универсального
стандарта. Это стартовые guardrails данного комплекта. Настрой их после 5–10
реальных задач по времени ревью, числу возвратов и качеству передачи контекста.
