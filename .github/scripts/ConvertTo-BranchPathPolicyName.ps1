function ConvertTo-BranchPathPolicyName {
    param(
        [Parameter(Mandatory)]
        [string]$BranchName
    )

    if ($BranchName.StartsWith('dependabot/', [StringComparison]::OrdinalIgnoreCase)) {
        return "feature/$BranchName"
    }

    return $BranchName
}
