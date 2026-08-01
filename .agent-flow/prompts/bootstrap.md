# Prompt: Bootstrap проекта

Прочитай корневой `AGENTS.md`, `.agent-flow/POLICY.md` и текущий
`.agent-flow/PROJECT.md`.

Работай в read-only режиме относительно production-кода. Разрешено менять только
`.agent-flow/PROJECT.md`.

1. Определи реальные языки, framework, package/build tools и repo layout.
2. Найди entry points, модули, storage, integrations и deployment artifacts.
3. Найди CI-команды, test suites, lint/type/build/quality/security checks.
4. Найди существующие repository instructions и architecture docs.
5. Построй основной request/event/data flow со ссылками на пути и symbols.
6. Выведи доменные/технические инварианты только из evidence; неизвестное пометь
   `UNKNOWN` и сформулируй вопрос человеку.
7. Найди compatibility surfaces, sensitive areas, generated paths,
   observability и rollback mechanisms.
8. Безопасно запусти быстрые команды проверки, если окружение готово. Не
   устанавливай зависимости и не меняй систему без разрешения.
9. Заполни `PROJECT.md` компактно. Не копируй большие куски README или кода.
10. Покажи человеку:
    - архитектурную карту;
    - пять наиболее важных инвариантов;
    - проверенные и непроверенные команды;
    - неизвестные доменные решения;
    - чувствительные зоны.

Остановись. Не ставь `HUMAN_APPROVED` самостоятельно и не начинай фичу.

