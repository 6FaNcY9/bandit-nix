export default {
  extends: ["@commitlint/config-conventional"],
  ignores: [
    // Allow temporary planning commits used in iterative Copilot PR workflows.
    (message) => message === "Initial plan",
    // Allow GitHub Copilot Autofix commits which don't follow conventional commit format.
    (message) => message.includes("Co-authored-by: Copilot Autofix"),
  ],
};
