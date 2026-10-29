# Optional Windows CI

To enable this template, copy windows.yml into .github/workflows/windows.yml using a GitHub login authorized to manage workflows, then commit it. GitHub OAuth tokens need the workflow scope for that operation.

The job builds and tests the unsigned MSIX on Windows. It does not sign packages, install the extension, or access signing keys.