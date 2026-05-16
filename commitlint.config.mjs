export default {
  extends: ["@commitlint/config-conventional"],
  ignores: [
    // Allow GitHub Copilot Autofix commits which don't follow conventional commit format
    (message) => message.includes("Co-authored-by: Copilot Autofix"),
  ],
};
