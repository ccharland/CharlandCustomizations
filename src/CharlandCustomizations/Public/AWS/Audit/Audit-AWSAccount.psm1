<#
.SYNOPSIS
AWS Account Audit PowerShell Module

.DESCRIPTION
This module provides a collection of PowerShell functions for auditing AWS accounts and resources.
It includes functions for analyzing EC2 instances, security groups, IAM resources, S3 buckets,
and other AWS services without working with CloudFormation templates.

.NOTES
Author: Generated from aws-templates-tools-snippets repository
Version: 1.0
Created: August 2025

This module excludes CloudFormation template processing functions which are available
in the TemplateProcessing.psm1 module.
#>

# Load private helper functions needed by this nested module (added by Kiro, aws-common-params spec)
. "$PSScriptRoot/../../../Private/New-AWSParamSplat.ps1"
. "$PSScriptRoot/../../Test-CHARAWSCmdlet.ps1"

# ================================================================================================
# Get-CHAREC2SGInUse Function
# ================================================================================================

<#
.SYNOPSIS
    Shows the resources associated with each EC2 Security Group in a region.
.DESCRIPTION
    Shows EC2 Security group and its associated resources. This includes: Instances, Network Interfaces, Load Balancers, Endpoints, Databases, Client Endpoints, Lambda Functions, ElastiCache Clusters, MSK Clusters, OpenSearch Domains, Redshift Clusters, EMR Clusters, DocumentDB Clusters, Neptune Clusters, MQ Brokers, FSx File Systems, Directories, WorkSpaces and SageMaker Notebooks.
    The script will return a list of security groups and the resources associated with them. It will also show the number of resources associated with each security group.

.PARAMETER Region
        The AWS region to use. If not specified, the default region will be used.
.PARAMETER GroupId
        The security group ID to check. If not specified, all security groups in the region will be checked.
.PARAMETER ProfileName
        The AWS credential profile name to use.
.PARAMETER AccessKey
        The AWS access key for authentication.
.PARAMETER SecretKey
        The AWS secret key for authentication.
.PARAMETER SessionToken
        The AWS session token for temporary credentials.
.PARAMETER Credential
        An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
        The location of the credentials file to use.
.PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
.INPUTS
    Amazon.EC2.Model.SecurityGroup
        Used to specify the security group ID. This is the ID of the security group to check for associated resources.

.NOTES
    Not all types have been tested

.OUTPUTS
AWS.EC2.SecurityGroupUsage

    The output will be in the form of a PowerShell object with the following properties:
        SecurityGroupId
        SecurityGroupName
        UsedByCount
        AssociatedInstances
        AssociatedNetworkInterfaces
        AssociatedLoadBalancers
        AssociatedEndpoints
        AssociatedDatabases
        AssociatedClientEndpoints
        AssociatedLambdaFunctions
        AssociatedElastiCacheClusters
        AssociatedMSKClusters
        AssociatedOpenSearchDomains
        AssociatedRedshiftClusters
        AssociatedEMRClusters
        AssociatedDocumentDBClusters
        AssociatedNeptuneClusters
        AssociatedMQBrokers
        AssociatedFSxFileSystems
        AssociatedDirectories
        AssociatedWorkSpaces
        AssociatedSageMakerNotebooks

    Example Output:
SecurityGroupId                : sg-12345678
SecurityGroupName              : my-security-group
UsedByCount                    : 3
AssociatedInstances            : i-12345678, i-87654321
AssociatedNetworkInterfaces    : eni-12345678
AssociatedLoadBalancers        : my-load-balancer
AssociatedEndpoints            :
AssociatedDatabases            :
AssociatedClientEndpoints      :
AssociatedLambdaFunctions      :
AssociatedElastiCacheClusters  :
AssociatedMSKClusters          :
AssociatedOpenSearchDomains    :
AssociatedRedshiftClusters     :
AssociatedEMRClusters          :
AssociatedDocumentDBClusters   :
AssociatedNeptuneClusters      :
AssociatedMQBrokers            :
AssociatedFSxFileSystems       :
AssociatedDirectories          :
AssociatedWorkSpaces           :
AssociatedSageMakerNotebooks   :

.EXAMPLE
    Get-CHAREC2SGInUse
    # Gets all security groups in the default region and shows their associated resources.

.EXAMPLE
    Get-CHAREC2SGInUse -Region us-west-2
    # Gets all security groups in the us-west-2 region and shows their associated resources.

.EXAMPLE
    Get-CHAREC2SGInUse -GroupId sg-12345678
    # Gets the security group with the ID sg-12345678 and shows its associated resources.

.EXAMPLE
    Get-EC2SecurityGroup -GroupId sg-12345678 | Get-CHAREC2SGInUse
    # Gets the security group with the ID sg-12345678 using the pipeline and shows its associated resources.

#>
function Get-CHAREC2SGInUse {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$GroupId = @(),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )
    begin {
        @(
            'Get-EC2SecurityGroup',
            'Get-ELB2LoadBalancer',
            'Get-RDSDBInstance',
            'Get-LMFunctionList',
            'Get-ECCacheCluster',
            'Get-MSKClusterList',
            'Get-NPTDBCluster',
            'Get-MQBrokerList',
            'Get-FSXFileSystem',
            'Get-DSDirectory',
            'Get-WKSWorkspace',
            'Get-SMNotebookInstanceList',
            'Get-OSDomainNameList',
            'Get-RSCluster',
            'Get-EMRClusterList',
            'Get-DOCDBCluster',
            'Get-ECSClusterList',
            'Get-EFSFileSystem',
            'Get-CBProjectList',
            'Get-DAXCluster',
            'Get-TFRServerList',
            'Get-GLUEConnectionList'
        ) | Test-CHARAWSCmdlet | Out-Null

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        try {
            if ($GroupId.Count -eq 0) {
                Write-Verbose "No security groups specified. Getting all security groups in the specified region"
                Write-Progress -Activity 'Get Security Group List:' -Status 'In Progress'
                $GroupId = (Get-EC2SecurityGroup @awsParams).GroupId
                if ($GroupId.Count -eq 0) {
                    throw "No security groups found in the specified region"
                }
            }
        }
        catch {
            throw "No security groups found in the specified region"
        }
        finally {
            Write-Progress -Activity 'Get Security Group List:' -Completed
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Instances'
        try {
            $InstancesMaster = Get-EC2Instance @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2Instance: Command not found, skipping"
            $InstancesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2Instance: Insufficient permissions, skipping"
                $InstancesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'NetworkInterfaces'
        try {
            $NetworkInterfaceMaster = Get-EC2NetworkInterface @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2NetworkInterface: Command not found, skipping"
            $NetworkInterfaceMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2NetworkInterface: Insufficient permissions, skipping"
                $NetworkInterfaceMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'LoadBalancer'
        try {
            $LoadBalancerMaster = Get-ELB2LoadBalancer @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ELB2LoadBalancer: Command not found, skipping"
            $LoadBalancerMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ELB2LoadBalancer: Insufficient permissions, skipping"
                $LoadBalancerMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EndPoints'
        try {
            $EndPointsMaster = Get-EC2VPCEndpoint @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2VPCEndpoint: Command not found, skipping"
            $EndPointsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2VPCEndpoint: Insufficient permissions, skipping"
                $EndPointsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Databases'
        try {
            $DatabasesMaster = Get-RDSDBInstance @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-RDSDBInstance: Command not found, skipping"
            $DatabasesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-RDSDBInstance: Insufficient permissions, skipping"
                $DatabasesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ClientEndpoints'
        try {
            $VPNCLientEndpointMaster = Get-EC2ClientVpnEndpoint @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EC2ClientVpnEndpoint: Command not found, skipping"
            $VPNCLientEndpointMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EC2ClientVpnEndpoint: Insufficient permissions, skipping"
                $VPNCLientEndpointMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Lambda'
        try {
            $LambdaFunctionsMaster = Get-LMFunctionList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-LMFunctionList: Command not found, skipping"
            $LambdaFunctionsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-LMFunctionList: Insufficient permissions, skipping"
                $LambdaFunctionsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ElasticCache'
        try {
            $ElastiCacheClustersMaster = Get-ECCacheCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ECCacheCluster: Command not found, skipping"
            $ElastiCacheClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ECCacheCluster: Insufficient permissions, skipping"
                $ElastiCacheClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'MSK'
        try {
            $MSKClustersMaster = Get-MSKClusterList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-MSKClusterList: Command not found, skipping"
            $MSKClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-MSKClusterList: Insufficient permissions, skipping"
                $MSKClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Neptune'
        try {
            $NeptuneClustersMaster = Get-NPTDBCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-NPTDBCluster: Command not found, skipping"
            $NeptuneClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-NPTDBCluster: Insufficient permissions, skipping"
                $NeptuneClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'MQBroker'
        try {
            $MQBrokersMaster = Get-MQBrokerList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-MQBrokerList: Command not found, skipping"
            $MQBrokersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-MQBrokerList: Insufficient permissions, skipping"
                $MQBrokersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'FSX'
        try {
            $FSxFileSystemsMaster = Get-FSXFileSystem @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-FSXFileSystem: Command not found, skipping"
            $FSxFileSystemsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-FSXFileSystem: Insufficient permissions, skipping"
                $FSxFileSystemsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Directory'
        try {
            $DirectoriesMaster = Get-DSDirectory @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DSDirectory: Command not found, skipping"
            $DirectoriesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DSDirectory: Insufficient permissions, skipping"
                $DirectoriesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Workspace'
        try {
            $WorkSpacesMaster = Get-WKSWorkspace @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-WKSWorkspace: Command not found, skipping"
            $WorkSpacesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-WKSWorkspace: Insufficient permissions, skipping"
                $WorkSpacesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'SageMaker'

        try {
            $SageMakerNotebookInstanceListMaster = Get-SMNotebookInstanceList @awsParams | ForEach-Object { Get-SMNotebookInstance @awsParams }
        }
        catch {
            $SageMakerNotebookInstanceListMaster = $null
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'OpenSearch'
        try {
            $OpenSearchDomainsMaster = Get-OSDomainNameList @awsParams | ForEach-Object {
                Get-OSDomainConfig -DomainName $_.DomainName @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-OSDomainNameList: Command not found, skipping"
            $OpenSearchDomainsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-OSDomainNameList: Insufficient permissions, skipping"
                $OpenSearchDomainsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Redshift'
        try {
            $RedshiftClustersMaster = Get-RSCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-RSCluster: Command not found, skipping"
            $RedshiftClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-RSCluster: Insufficient permissions, skipping"
                $RedshiftClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EMR'
        try {
            $EMRClustersMaster = Get-EMRClusterList @awsParams | Where-Object {
                $_.Status.State -notin @('TERMINATED', 'TERMINATED_WITH_ERRORS')
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EMRClusterList: Command not found, skipping"
            $EMRClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EMRClusterList: Insufficient permissions, skipping"
                $EMRClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'DocumentDB'
        try {
            $DocumentDBClustersMaster = Get-DOCDBCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DOCDBCluster: Command not found, skipping"
            $DocumentDBClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DOCDBCluster: Insufficient permissions, skipping"
                $DocumentDBClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'ECS'
        try {
            $ECSServicesMaster = @()
            $clusterArns = Get-ECSClusterList @awsParams
            foreach ($clusterArn in $clusterArns) {
                $serviceArns = Get-ECSClusterService -Cluster $clusterArn @awsParams
                if ($serviceArns) {
                    $ECSServicesMaster += Get-ECSService -Cluster $clusterArn -Service $serviceArns @awsParams
                }
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-ECSClusterList: Command not found, skipping"
            $ECSServicesMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-ECSClusterList: Insufficient permissions, skipping"
                $ECSServicesMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'EFS'
        try {
            $EFSMountTargetsMaster = @()
            $fileSystems = Get-EFSFileSystem @awsParams
            foreach ($fs in $fileSystems) {
                $EFSMountTargetsMaster += Get-EFSMountTarget -FileSystemId $fs.FileSystemId @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-EFSFileSystem: Command not found, skipping"
            $EFSMountTargetsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-EFSFileSystem: Insufficient permissions, skipping"
                $EFSMountTargetsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'CodeBuild'
        try {
            $CodeBuildProjectsMaster = @()
            $projectNames = Get-CBProjectList @awsParams
            if ($projectNames) {
                $CodeBuildProjectsMaster = Get-CBBatchProject -Name $projectNames @awsParams
            }
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-CBProjectList: Command not found, skipping"
            $CodeBuildProjectsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-CBProjectList: Insufficient permissions, skipping"
                $CodeBuildProjectsMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'DAX'
        try {
            $DAXClustersMaster = Get-DAXCluster @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-DAXCluster: Command not found, skipping"
            $DAXClustersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-DAXCluster: Insufficient permissions, skipping"
                $DAXClustersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'TransferFamily'
        try {
            $TransferServersMaster = Get-TFRServerList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-TFRServerList: Command not found, skipping"
            $TransferServersMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-TFRServerList: Insufficient permissions, skipping"
                $TransferServersMaster = @()
            }
            else { throw }
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Glue'
        try {
            $GlueConnectionsMaster = Get-GLUEConnectionList @awsParams
        }
        catch [System.Management.Automation.CommandNotFoundException] {
            Write-Warning "Get-GLUEConnectionList: Command not found, skipping"
            $GlueConnectionsMaster = @()
        }
        catch {
            if ($_.Exception.Message -match 'AccessDenied|UnauthorizedAccess|not authorized') {
                Write-Warning "Get-GLUEConnectionList: Insufficient permissions, skipping"
                $GlueConnectionsMaster = @()
            }
            else { throw }
        }

        # Initialize an array to store results
        $Results = @()
        # start progress display
        $Total = $GroupId.Count
        $Count = 0
        Write-Progress -Activity 'Get Resource List:' -Completed
    }

    process {
        foreach ($SG in $GroupId) {
            $SecurityGroup = Get-EC2SecurityGroup @awsParams -GroupId $SG
            $Count++
            Write-Verbose "Count: $count"
            Write-Verbose "Total: $Total"
            Write-Progress -Activity "Processing SG: $SG" -Status 'Progress:' -PercentComplete ($Count / $Total * 100)
            $UsedByCount = 0
            $Instances = $InstancesMaster | Where-Object {
                $_.Instances.SecurityGroups.GroupId -contains $SG
            }

            $UsedByCount += $Instances.Count
            $NetworkInterface = $NetworkInterfaceMaster | Where-Object {
                $_.Groups.GroupId -contains $SG
            }
            $UsedByCount += $NetworkInterface.Count
            # Get associated Load Balancers
            $LoadBalancers = $LoadBalancerMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $LoadBalancers.Count

            $Endpoints = $EndpointsMaster | Where-Object {
                $_.Groups.GroupId -contains $SG
            }
            $UsedByCount += $Endpoints.Count
            $Databases = $DatabasesMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $Databases.Count
            $VPNClientEndpoints = $VPNCLientEndpointMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $VPNClientEndpoints.Count

            # Get associated Lambda functions in VPC
            $LambdaFunctions = $LambdaFunctionsMaster | Where-Object {
                $null -ne $_.VpcConfig -and $_.VpcConfig.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $LambdaFunctions.Count

            # Get associated ElastiCache clusters
            $ElastiCacheClusters = $ElastiCacheClustersMaster | Where-Object {
                $_.SecurityGroups.SecurityGroupId -contains $SG
            }
            $UsedByCount += $ElastiCacheClusters.Count

            # Get associated Amazon MSK clusters
            $MSKClusters = $MSKClustersMaster | ForEach-Object {
                $ClusterInfo = Get-MSKCluster -ClusterArn $_.ClusterArn @awsParams
                if ($ClusterInfo.BrokerNodeGroupInfo.SecurityGroups -contains $SG) {
                    $_
                }
            }
            $UsedByCount += $MSKClusters.Count

            # Get associated Neptune clusters
            $NeptuneClusters = $NeptuneClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $NeptuneClusters.Count
            # Get associated Amazon MQ brokers
            $MQBrokers = $MQBrokersMaster | ForEach-Object { Get-MQBroker @awsParams | Where-Object {
                    $_.SecurityGroups -contains $SG }
            }
            $UsedByCount += $MQBrokers.Count

            # Get associated FSx file systems
            $FSxFileSystems = $FSxFileSystemsMaster | Where-Object {
                $_.NetworkInterfaceIds | ForEach-Object {
                    $ENI = Get-EC2NetworkInterface -NetworkInterfaceId $_ @awsParams
                    $ENI.Groups.GroupId -contains $SG
                }
            }
            $UsedByCount += $FSxFileSystems.Count
            # Get associated Directory Service directories
            $Directories = $DirectoriesMaster | Where-Object {
                $_.VpcSettings.SecurityGroupId -eq $SG
            }
            $UsedByCount += $Directories.Count

            # Get associated WorkSpaces
            $WorkSpaces = $WorkSpacesMaster | ForEach-Object {
                $WorkspaceId = $_.WorkspaceId
                $WorkspaceDetails = Get-WKSWorkspace -WorkspaceId $WorkspaceId @awsParams
                if ($WorkspaceDetails.SecurityGroupIds -contains $SG) {
                    $_
                }
            }
            $UsedByCount += $WorkSpaces.Count

            if ($SageMakerNotebookInstanceListMaster.count) {
                $SageMakerNotebooks = $SageMakerNotebookInstanceListMaster | Where-Object {
                    $_.SecurityGroups -contains $SG }
            }
            else {
                $SageMakerNotebooks = @()
            }
            $UsedByCount += $SageMakerNotebooks.Count

            # Get associated OpenSearch domains
            $OpenSearchDomains = $OpenSearchDomainsMaster | Where-Object {
                $_.VPCOptions.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $OpenSearchDomains.Count

            # Get associated Redshift clusters
            $RedshiftClusters = $RedshiftClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $RedshiftClusters.Count

            # Get associated EMR clusters
            $EMRClusters = @()
            foreach ($emrCluster in $EMRClustersMaster) {
                try {
                    $emrDetail = Get-EMRCluster -ClusterId $emrCluster.Id @awsParams
                    if ($emrDetail.Ec2InstanceAttributes.EmrManagedMasterSecurityGroup -eq $SG -or
                        $emrDetail.Ec2InstanceAttributes.EmrManagedSlaveSecurityGroup -eq $SG -or
                        $emrDetail.Ec2InstanceAttributes.AdditionalMasterSecurityGroups -contains $SG -or
                        $emrDetail.Ec2InstanceAttributes.AdditionalSlaveSecurityGroups -contains $SG) {
                        $EMRClusters += $emrCluster
                    }
                }
                catch {
                    Write-Verbose "Get-EMRCluster ($($emrCluster.Id)): $_"
                }
            }
            $UsedByCount += $EMRClusters.Count

            # Get associated DocumentDB clusters
            $DocumentDBClusters = $DocumentDBClustersMaster | Where-Object {
                $_.VpcSecurityGroups.VpcSecurityGroupId -contains $SG
            }
            $UsedByCount += $DocumentDBClusters.Count

            # Get associated ECS services (awsvpc mode)
            $ECSServices = $ECSServicesMaster | Where-Object {
                $_.NetworkConfiguration.AwsvpcConfiguration.SecurityGroups -contains $SG
            }
            $UsedByCount += $ECSServices.Count

            # Get associated EFS mount targets
            $EFSMountTargets = $EFSMountTargetsMaster | Where-Object {
                $_.SecurityGroups -contains $SG
            }
            $UsedByCount += $EFSMountTargets.Count

            # Get associated CodeBuild projects
            $CodeBuildProjects = $CodeBuildProjectsMaster | Where-Object {
                $_.VpcConfig.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $CodeBuildProjects.Count

            # Get associated DAX clusters
            $DAXClusters = $DAXClustersMaster | Where-Object {
                $_.SecurityGroups.SecurityGroupIdentifier -contains $SG
            }
            $UsedByCount += $DAXClusters.Count

            # Get associated Transfer Family servers
            $TransferServers = $TransferServersMaster | Where-Object {
                $_.StructuredLogDestinations -contains $SG -or $_.SecurityGroupIds -contains $SG
            }
            $UsedByCount += $TransferServers.Count

            # Get associated Glue connections
            $GlueConnections = $GlueConnectionsMaster | Where-Object {
                $_.PhysicalConnectionRequirements.SecurityGroupIdList -contains $SG
            }
            $UsedByCount += $GlueConnections.Count

            # Add results to the array
            $Results += [PSCustomObject]@{
                PSTypeName                    = 'AWS.EC2.SecurityGroupUsage'
                SecurityGroupId               = $SG
                SecurityGroupName             = $SecurityGroup.GroupName
                SecurityGroupDescription      = $SecurityGroup.Description
                UsedByCount                   = $UsedByCount
                AssociatedInstances           = $Instances.Instances.InstanceId -join ', '
                NetworkInterface              = $NetworkInterface.NetworkInterfaceId -join ', '
                AssociatedLoadBalancers       = $LoadBalancers.LoadBalancerName -join ', '
                AssociatedEndpoints           = $Endpoints.VpcEndpointId -join ', '
                AssociatedDatabases           = $Databases.DBInstanceIdentifier -join ', '
                AssociatedVPNClientEndpoints  = $VPNClientEndpoints.VpnClientConnectionId -join ', '
                AssociatedLambdaFunctions     = $LambdaFunctions.FunctionName -join ', '
                AssociatedElastiCacheClusters = $ElastiCacheClusters.CacheClusterId -join ', '
                AssociatedMSKClusters         = $MSKClusters.ClusterName -join ', '
                AssociatedOpenSearchDomains   = $OpenSearchDomains.DomainName -join ', '
                AssociatedRedshiftClusters    = $RedshiftClusters.ClusterIdentifier -join ', '
                AssociatedEMRClusters         = $EMRClusters.Id -join ', '
                AssociatedDocumentDBClusters  = $DocumentDBClusters.DBClusterIdentifier -join ', '
                AssociatedNeptuneClusters     = $NeptuneClusters.DBClusterIdentifier -join ', '
                AssociatedMQBrokers           = $MQBrokers.BrokerId -join ', '
                AssociatedFSxFileSystems      = $FSxFileSystems.FileSystemId -join ', '
                AssociatedDirectories         = $Directories.DirectoryId -join ', '
                AssociatedWorkSpaces          = $WorkSpaces.WorkspaceId -join ', '
                AssociatedSageMakerNotebooks  = $SageMakerNotebooks.NotebookInstanceName -join ', '
                AssociatedECSServices         = $ECSServices.ServiceName -join ', '
                AssociatedEFSMountTargets     = $EFSMountTargets.MountTargetId -join ', '
                AssociatedCodeBuildProjects   = $CodeBuildProjects.Name -join ', '
                AssociatedDAXClusters         = $DAXClusters.ClusterName -join ', '
                AssociatedTransferServers     = $TransferServers.ServerId -join ', '
                AssociatedGlueConnections     = $GlueConnections.Name -join ', '
            }
        }
    }

    end {
        return $Results
    }
}

# ================================================================================================
# Out-CHARAWSSupportingInfo Function
# ================================================================================================

function Out-CHARAWSSupportingInfo {
    <#
    .SYNOPSIS
        Exports AWS account supporting information to text files.
    .DESCRIPTION
        Retrieves and exports SSM parameters, Secrets Manager secret names, and
        CloudFormation exports for documentation or migration purposes.
    .PARAMETER Region
        AWS region to query. Defaults to current default region.
    .PARAMETER RootPath
        Root directory for output files. Defaults to current directory.
    .PARAMETER ProfileName
        AWS credential profile name.
    .PARAMETER AccessKey
        The AWS access key for authentication.
    .PARAMETER SecretKey
        The AWS secret key for authentication.
    .PARAMETER SessionToken
        The AWS session token for temporary credentials.
    .PARAMETER Credential
        An AWSCredentials object for authentication.
    .PARAMETER ProfileLocation
        The location of the credentials file to use.
    .PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
    .EXAMPLE
        Out-CHARAWSSupportingInfo
    .EXAMPLE
        Out-CHARAWSSupportingInfo -Region us-west-2 -RootPath C:\AWSInfo
    .OUTPUTS
        Creates files in <RootPath>/<AccountId>/<Region>/:
        - SSMParameters.txt
        - Secrets.txt (names only, not values)
        - CFNExports.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )
    @(
        'Get-STSCallerIdentity',
        'Get-SSMParameterList',
        'Get-SECSecretList',
        'Get-CFNExport'
    ) | Test-CHARAWSCmdlet | Out-Null


    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    $AccountId = (Get-STSCallerIdentity @awsParams).Account
    $RegionDisplay = if ($awsParams.ContainsKey('Region')) { $awsParams['Region'] } else { (Get-DefaultAWSRegion).Region }
    Write-Verbose "AccountId: $AccountId | Region: $RegionDisplay"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $RegionDisplay)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-SSMParameterList @awsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'SSMParameters.txt') -Force

    Get-SECSecretList @awsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'Secrets.txt') -Force

    Get-CFNExport @awsParams |
    Select-Object Name, Value |
    Out-File -FilePath (Join-Path $OutputDir 'CFNExports.txt') -Force

    Write-Output "Exported supporting info to: $OutputDir"
}

# ================================================================================================
# Out-CHARAWSNetworkingComponent Function
# ================================================================================================

function Out-CHARAWSNetworkingComponent {
    <#
    .SYNOPSIS
        Exports AWS VPC networking configuration to text files.
    .DESCRIPTION
        Retrieves and exports VPC networking configuration including VPN connections,
        VPCs, subnets, route tables, prefix lists, transit gateway route tables, and
        transit gateway attachments. Output is organized by account ID and region.
    .PARAMETER Region
        AWS region to query. Defaults to current default region.
    .PARAMETER RootPath
        Root directory for output files. Defaults to current directory.
    .PARAMETER ProfileName
        AWS credential profile name.
    .PARAMETER AccessKey
        The AWS access key for authentication.
    .PARAMETER SecretKey
        The AWS secret key for authentication.
    .PARAMETER SessionToken
        The AWS session token for temporary credentials.
    .PARAMETER Credential
        An AWSCredentials object for authentication.
    .PARAMETER ProfileLocation
        The location of the credentials file to use.
    .PARAMETER EndpointUrl
        A custom endpoint URL to use for the AWS service.
    .EXAMPLE
        Out-CHARAWSNetworkingComponent
    .EXAMPLE
        Out-CHARAWSNetworkingComponent -Region us-east-1 -RootPath C:\AWS
    .OUTPUTS
        Creates files in <RootPath>/<AccountId>/<Region>/:
        - VPNConnections.txt
        - VPCs.txt
        - Subnets.txt
        - RouteTables.txt
        - PrefixLists.txt
        - TransitGatewayRouteTables.txt
        - TransitGatewayAttachments.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )
    @(
        'Get-STSCallerIdentity',
        'Get-EC2VpnConnection'
    ) | Test-CHARAWSCmdlet | Out-Null


    $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

    $AccountId = (Get-STSCallerIdentity @awsParams).Account
    $RegionDisplay = if ($awsParams.ContainsKey('Region')) { $awsParams['Region'] } else { (Get-DefaultAWSRegion).Region }
    Write-Verbose "AccountId: $AccountId | Region: $RegionDisplay"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $RegionDisplay)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-EC2VpnConnection @awsParams |
    Select-Object VpnConnectionId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPNConnections.txt') -Force

    Get-EC2Vpc @awsParams |
    Select-Object VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock,
    @{Name = 'AssociatedCidrBlocks'; Expression = { ($_.CidrBlockAssociationSet | ForEach-Object { $_.CidrBlock }) -join ', ' } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPCs.txt') -Force

    Get-EC2Subnet @awsParams |
    Select-Object VpcId, SubnetId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock, AvailabilityZone, AvailableIpAddressCount |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'Subnets.txt') -Force

    Get-EC2RouteTable @awsParams |
    Select-Object RouteTableId, VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    @{Name = 'AssociationCount'; Expression = { ($_.Associations | Measure-Object).Count } } |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'RouteTables.txt') -Force

    Get-EC2ManagedPrefixList @awsParams |
    Format-Table PrefixListId, PrefixListName |
    Out-File -FilePath (Join-Path $OutputDir 'PrefixLists.txt') -Force

    Get-EC2TransitGatewayRouteTable @awsParams |
    Select-Object TransitGatewayRouteTableId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'TransitGatewayRouteTables.txt') -Force

    Get-EC2TransitGatewayAttachment @awsParams |
    Select-Object `
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    ResourceId,
    @{Name = 'AssociatedRT'; Expression = { ($_.Association | Where-Object { $_.State -eq 'associated' }).TransitGatewayRouteTableId } },
    TransitGatewayAttachmentId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'TransitGatewayAttachments.txt') -Force

    Write-Output "Exported networking components to: $OutputDir"
}

# ================================================================================================
# Get-CHARIAMAuditList Function
# ================================================================================================

<#
.SYNOPSIS
    Consolidated IAM Credential report from multiple accounts into a single report.

.DESCRIPTION
    Invokes Get-IAMCredentialReport for each profile for multiple accounts, and outputs the result into a text array
    that is CSV formatted.

    For information on the report format, refer to the AWS Identity and Access Mangement User
    Guide section "Getting credentail reports."

.PARAMETER ProfileName
    List of AWS Profiles that have permissison to call:

    iam:GenerateCredentailReport
    iam:GetCredentialReport

.EXAMPLE
    PS> $profile-list= @(
        'Profile1',
        'Profile2'
    )

    PS> Get-CHARIAMAuditList -ProfileName $profile-list  |out-file -Path '\reports\complete-credentails.csv'

.NOTES
    https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_getting-report.html?icmpid=docs_iam_help_panel#id_credentials_understanding_the_report_format
#>
function Get-CHARIAMAuditList {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $ProfileName
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Request-IAMCredentialReport'

        $allProfiles = @()
    }

    process {
        $allProfiles += $ProfileName
    }

    end {
        do {
            $RequestState = $allProfiles | ForEach-Object { Request-IAMCredentialReport -ProfileName $_ }
            Write-Verbose 'Waiting for report to generate'
            Start-Sleep -Seconds 5
        } while (($RequestState.State -notlike 'COMPLETE').count -ne 0)

        Write-Verbose 'Credential report complete'
        $SkipLines = 0
        $Results = foreach ($ProfileItem in $allProfiles) {
            Get-IAMCredentialReport -AsTextArray -ProfileName $ProfileItem | Select-Object -Skip $SkipLines
            $skiplines = 1
        }
        return $Results
    }
}

# ================================================================================================
# Get-CHARGlobalAuditReportItem Function
# ================================================================================================

<#
.SYNOPSIS
    Create list of AWS resources in use.
.DESCRIPTION
    First version, just to get the basics in place. Provides a count of various AWS resources
    across specified regions.
.PARAMETER Region
    The AWS region(s) to audit. Defaults to us-east-1 if not specified.
.EXAMPLE
    PS C:\> Get-CHARGlobalAuditReportItem
    Gets a count of AWS resources in the default region (us-east-1)
.EXAMPLE
    PS C:\> Get-CHARGlobalAuditReportItem -Region @("us-east-1", "us-west-2")
    Gets a count of AWS resources in multiple regions
.INPUTS
    String array of region names
.OUTPUTS
    PSCustomObject with resource counts by region
.NOTES
    General notes - this is a first version to get the basics in place
#>
function Get-CHARGlobalAuditReportItem {
    [CmdletBinding()]
    param(
        [string[]]$Region = @('us-east-1'),

        # AWS common parameters (Region excluded - handled by $Region array above)
        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )
    @(
        'Get-STSCallerIdentity',
        'Get-Ec2Instance',
        'Get-CFDistributionList',
        'Get-ELB2LoadBalancer',
        'Get-ELBLoadBalancer',
        'Get-ASAutoScalingGroup',
        'Get-RDSDBInstance',
        'Get-EFSFileSystem',
        'Get-ECSClusterList',
        'Get-EKSClusterList',
        'Get-KMSKeyList',
        'Get-LMFunctionList',
        'Get-ACMCertificateList',
        'Get-SECSecretList',
        'Get-DDBTableList',
        'Get-RSCluster',
        'Get-SQSQueue',
        'Get-SNSTopic',
        'Get-SFNStateMachineList',
        'Get-DSDirectory',
        'Get-FRCForecastList',
        'Get-SGGateway'
    ) | Test-CHARAWSCmdlet | Out-Null


    # Build base AWS params (excludes Region since we iterate over regions)
    $baseAwsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    $baseAwsParams.Remove('Region') | Out-Null

    $output = @()
    foreach ($RegionName in $Region) {
        $regionParams = $baseAwsParams.Clone()
        $regionParams['Region'] = $RegionName

        Write-Output $RegionName
        $RegionResults = New-Object -TypeName 'PSCustomObject' -Property @{
            account          = (Get-STSCallerIdentity @regionParams).Account
            region           = $RegionName
            VMCount          = (Get-Ec2Instance @regionParams).count
            CloudFront       = (Get-CFDistributionList @regionParams).count
            LoadBalancer     = (Get-ELB2LoadBalancer @regionParams).count + (Get-ELBLoadBalancer @regionParams).count
            AutoScaling      = (Get-ASAutoScalingGroup @regionParams).count
            RDS              = (Get-RDSDBInstance @regionParams).count
            EFS              = (Get-EFSFileSystem @regionParams).count
            ECS              = (Get-ECSClusterList @regionParams).count
            EKS              = (Get-EKSClusterList @regionParams).count
            KMS              = (Get-KMSKeyList @regionParams).count
            Lambda           = (Get-LMFunctionList @regionParams).count
            Certs            = (Get-ACMCertificateList @regionParams).count
            Secrets          = (Get-SECSecretList @regionParams).count
            DynamoDB         = (Get-DDBTableList @regionParams).count
            RDS_Maria        = (Get-RDSDBInstance @regionParams -filter @{name = 'engine'; values = 'mariadb' }).count
            Redshift         = (Get-RSCluster @regionParams).count
            SNS_SQS          = (Get-SQSQueue @regionParams).count + (Get-SNSTopic @regionParams).count
            Step             = (Get-SFNStateMachineList @regionParams).count
            DirectoryService = (Get-DSDirectory @regionParams).count
            Forecast         = (Get-FRCForecastList @regionParams).count
            StorageGateway   = (Get-SGGateway @regionParams).count
        }

        $output += $RegionResults
    }
    return $output
}

# ================================================================================================
# Get-CHAREC2KeyTagNameStatus Function
# ================================================================================================

<#
.SYNOPSIS
 Tells you if a EC2 Key with tag name is on the listed resources.

.DESCRIPTION
 Good way of finding out if you're missing key items, like Name, Environment, for any EC2 object

.NOTES
 Provides some output that we can use.

.PARAMETER TagKey
 Tag key to search for, just a string.. Value is ignored (for now)

.PARAMETER taglist
 group object of tags, results of command:
  get-EC2Tag |group-object resourceid
  Must be in a group
  no error checking
  if null, will call above line to generate master list:

.PARAMETER filter
filter to pass to get-ec2tag

.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.OUTPUTS
PSobject
ResourceID, KeyPresent

.EXAMPLE
Get-CHAREC2KeyTagNameStatus -TagKey "Name"
Checks if all EC2 resources have a "Name" tag
#>
function Get-CHAREC2KeyTagNameStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]
        $TagKey,
        $taglist = $null,
        $filter = $null,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Get-EC2Tag'

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        if ($null -eq $taglist) {
            if ($filter) {
                $Taglist = Get-EC2Tag @awsParams -filter $filter | Group-Object resourceId
            }
            else {
                $Taglist = Get-EC2Tag @awsParams | Group-Object resourceId
            }
        }

        $output = @()

        foreach ($item in $taglist) {
            $result = New-Object -TypeName PSCustomObject
            $result | Add-Member -MemberType NoteProperty -Name 'ResourceId' -Value $item.name
            $result | Add-Member -MemberType NoteProperty -Name 'KeyName' -Value $TagKey

            foreach ($tag in $item.group) {
                if ($tag.key -eq $TagKey) {
                    break
                }
            }
            #process results
            if ($tag.key -eq $TagKey) {
                $result | Add-Member -MemberType NoteProperty -Name 'KeyPresent' -Value $True
            }
            else {
                $result | Add-Member -MemberType NoteProperty -Name 'KeyPresent' -Value $False
            }
            $output += $result
        }

        if ($output.count -ne $taglist.count) {
            throw 'Script error- Input item count does not match output item count'
        }
        return $output
    }
}

# ================================================================================================
# Get-CHAREC2SnapshotReport Function
# ================================================================================================

<#
.SYNOPSIS
    Gets a listing of EC2 snapshots for a region.

.DESCRIPTION
    Calls Get-EC2Snapshot in a batch format to audit accounts with thousands of
    snapshots. Retrieves all self-owned snapshots using pagination and returns
    each snapshot's metadata along with any associated tags as dynamic properties.

.PARAMETER MaxResults
    Maximum number of snapshots to retrieve per API call. Defaults to 200.
    Lower values reduce memory usage per batch; higher values reduce API calls.

.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.OUTPUTS
    PSCustomObject with the following properties:
    - SnapshotId: The snapshot identifier
    - VolumeId: The source volume identifier
    - StartTime: When the snapshot was initiated
    - Description: Snapshot description
    - State: Current snapshot state (pending, completed, error)
    - Tag:<TagName>: One dynamic property per tag on the snapshot

.EXAMPLE
    PS> Get-CHAREC2SnapshotReport
    Returns all self-owned snapshots in the current region with default batch size.

.EXAMPLE
    PS> Get-CHAREC2SnapshotReport -MaxResults 500 | Export-Csv -Path snapshots.csv -NoTypeInformation
    Exports all snapshots to CSV using larger batch size for fewer API calls.

.EXAMPLE
    PS> Get-CHAREC2SnapshotReport | Where-Object { $_.State -eq 'completed' } | Measure-Object
    Counts all completed snapshots in the current region.

.NOTES
    Uses $AWSHistory.LastServiceResponse.NextToken for pagination.
    The -OwnerId 'self' filter ensures only account-owned snapshots are returned.
#>
function Get-CHAREC2SnapshotReport {
    [CmdletBinding()]
    param(
        [int]$MaxResults = 200,

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Get-EC2Snapshot'

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        $output = @()
        $NextToken = $null

        do {
            #process in smaller groups
            Write-Information -MessageData "Fetching info on up to $($MaxResults) snapshots"
            $SnapshotList = Get-EC2Snapshot -OwnerId self -NextToken $NextToken -maxresult $MaxResults @awsParams
            $NextToken = $AWShistory.LastServiceResponse.NextToken
            $Message = 'Starting processing of ' + $SnapshotList.count + ' snapshots'
            Write-Information $Message

            foreach ($Snapshot in $SnapshotList) {
                $record = New-Object -TypeName PSCustomObject -Property ([ordered] @{
                        SnapshotId  = $Snapshot.SnapshotId
                        VolumeId    = $Snapshot.VolumeId
                        StartTime   = $Snapshot.StartTime
                        Description = $Snapshot.Description
                        State       = $Snapshot.State
                    })

                $Snapshot.Tags | Sort-Object Key | ForEach-Object {
                    Add-Member -InputObject $Record -NotePropertyName "Tag:$($_.key)" -NotePropertyValue $($_.value)
                }
                $output += $record
            }
            Write-Information "output size is $($output.count)"
        } while ($NextToken)
        return $output
    }
}

# ================================================================================================
# Get-CHAREC2VolumeReport Function
# ================================================================================================

<#
.SYNOPSIS
    Gets a report of all EC2 volumes in the current region
.DESCRIPTION
    Lists all EC2 volumes and their attachment status, including unattached volumes
.PARAMETER Region
    The AWS region to query.
.PARAMETER ProfileName
    The AWS credential profile name to use.
.PARAMETER AccessKey
    The AWS access key for authentication.
.PARAMETER SecretKey
    The AWS secret key for authentication.
.PARAMETER SessionToken
    The AWS session token for temporary credentials.
.PARAMETER Credential
    An AWSCredentials object for authentication.
.PARAMETER ProfileLocation
    The location of the credentials file to use.
.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.
.EXAMPLE
    Get-CHAREC2VolumeReport
    Gets all volumes in the current region
#>
function Get-CHAREC2VolumeReport {
    [CmdletBinding()]
    param(
        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Get-Ec2Volume'

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        $volist = Get-Ec2Volume @awsParams
        Write-Verbose "Number of volumes in region: $($volist.count) "
        $results = @()

        foreach ($item in $volist) {
            if ($item.state -eq 'available') {
                #instance not attached
                Write-Verbose "unattached volume $($item.volumeid)"
                $results += $item | Select-Object Volumeid, @{Name = 'InstanceID' ; Expression = { 'NoInstance' } }, Size, Iops, VolumeType
            }
            else {
                Write-Verbose "attached volume $($item.volumeid)"
                foreach ($attachment in $item.Attachments ) {
                    $results += $attachment | Select-Object VolumeId, InstanceId, @{Name = 'Size'; Expression = { $item.Size } },
                    @{Name = 'Iops'; Expression = { $item.Iops } }, @{Name = 'VolumeType'; Expression = { $item.VolumeType } }
                }
            }
        }
        return $results
    }
}

# ================================================================================================
# Start-CHAREC2RetryLoop Function
# ================================================================================================

<#
.SYNOPSIS
    Implements a retry loop for EC2 operations
.DESCRIPTION
    Provides a retry mechanism for EC2 operations that might fail due to temporary issues
.PARAMETER ScriptBlock
    The script block to execute
.PARAMETER MaxRetries
    Maximum number of retries (default: 3)
.PARAMETER DelaySeconds
    Delay between retries in seconds (default: 5)
.EXAMPLE
    Start-CHAREC2RetryLoop -ScriptBlock {Get-EC2Instance} -MaxRetries 5
#>
function Start-CHAREC2RetryLoop {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 3,
        [int]$DelaySeconds = 5
    )

    if (-not $PSCmdlet.ShouldProcess("EC2 Operation", "Execute with retry (max $MaxRetries attempts)")) {
        return
    }

    $attempt = 0
    do {
        $attempt++
        try {
            $result = & $ScriptBlock
            return $result
        }
        catch {
            if ($attempt -lt $MaxRetries) {
                Write-Warning "Attempt $attempt failed: $($_.Exception.Message). Retrying in $DelaySeconds seconds..."
                Start-Sleep -Seconds $DelaySeconds
            }
            else {
                throw "All $MaxRetries attempts failed. Last error: $($_.Exception.Message)"
            }
        }
    } while ($attempt -lt $MaxRetries)
}

# ================================================================================================
# Find-CHAROpenSecurityGroup Function
# ================================================================================================

<#
.SYNOPSIS
    Finds EC2 security groups with overly permissive inbound rules (0.0.0.0/0) on ports other than 80 and 443.

.DESCRIPTION
    Scans all security groups in the current AWS region for inbound rules that allow traffic
    from 0.0.0.0/0 or ::/0 to any port other than 80 and 443. These rules represent potential
    security risks.

.PARAMETER Region
    AWS region to scan. Uses the current default region if not specified.

.PARAMETER ProfileName
    AWS credential profile to use.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.PARAMETER AllowedPorts
    Ports that are acceptable to have open to the internet. Defaults to 80 and 443.

.EXAMPLE
    Find-CHAROpenSecurityGroup
    Scans the current region for overly permissive security groups.

.EXAMPLE
    Find-CHAROpenSecurityGroup -Region us-west-2 -AllowedPorts 80,443,8080
    Scans us-west-2, treating ports 80, 443, and 8080 as acceptable.
#>
function Find-CHAROpenSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int[]]$AllowedPorts = @(80, 443),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Get-EC2SecurityGroup'

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        try {
            Write-Verbose 'Retrieving security groups...'
            $securityGroups = Get-EC2SecurityGroup @awsParams

            if (-not $securityGroups) {
                Write-Verbose 'No security groups found.'
                Write-Output ([PSCustomObject]@{})
                return
            }

            Write-Verbose "Found $($securityGroups.Count) security groups. Checking inbound rules..."

            $findings = foreach ($sg in $securityGroups) {
                foreach ($rule in $sg.IpPermissions) {
                    # Check IPv4 ranges for 0.0.0.0/0
                    $openIpv4 = $rule.Ipv4Ranges | Where-Object { $_.CidrIp -eq '0.0.0.0/0' }
                    # Check IPv6 ranges for ::/0
                    $openIpv6 = $rule.Ipv6Ranges | Where-Object { $_.CidrIpv6 -eq '::/0' }

                    if ($openIpv4 -or $openIpv6) {
                        $fromPort = $rule.FromPort
                        $toPort = $rule.ToPort

                        # IpProtocol -1 means all traffic (all ports)
                        $isAllTraffic = $rule.IpProtocol -eq '-1'

                        # Check if the rule covers only allowed ports
                        $isAllowedOnly = (-not $isAllTraffic) -and
                        ($fromPort -eq $toPort) -and
                        ($fromPort -in $AllowedPorts)

                        if (-not $isAllowedOnly) {
                            # Determine which open CIDR triggered the finding
                            $openCidrs = @()
                            if ($openIpv4) { $openCidrs += '0.0.0.0/0' }
                            if ($openIpv6) { $openCidrs += '::/0' }

                            $portDisplay = if ($isAllTraffic) {
                                'All Ports'
                            }
                            elseif ($fromPort -eq $toPort) {
                                "$fromPort"
                            }
                            else {
                                "$fromPort-$toPort"
                            }

                            [PSCustomObject]@{
                                GroupId     = $sg.GroupId
                                GroupName   = $sg.GroupName
                                VpcId       = $sg.VpcId
                                Protocol    = if ($isAllTraffic) { 'All' } else { $rule.IpProtocol }
                                Ports       = $portDisplay
                                OpenCIDR    = $openCidrs -join ', '
                                Description = ($rule.Ipv4Ranges | Where-Object { $_.CidrIp -eq '0.0.0.0/0' } |
                                    Select-Object -First 1 -ExpandProperty Description) -as [string]
                            }
                        }
                    }
                }
            }

            if ($findings) {
                Write-Verbose "Found $($findings.Count) overly permissive rule(s) across security groups."
                $findings
            }
            else {
                Write-Verbose "No overly permissive inbound rules found. All 0.0.0.0/0 rules are limited to ports: $($AllowedPorts -join ', ')"
                return [PSCustomObject]@{}
            }
        }
        catch {
            Write-Error "Failed to retrieve security groups: $_"
        }
    }
}

<#
.SYNOPSIS
    Finds security groups that allow inbound traffic on common database ports.

.DESCRIPTION
    Scans all EC2 security groups in the current region and returns those with
    inbound rules permitting traffic on well-known database ports (MySQL, PostgreSQL,
    MSSQL, Oracle, Redis, MongoDB, etc.). Reports any source CIDR, not just
    0.0.0.0/0, so you can audit all DB-accessible security groups.

.PARAMETER Region
    AWS region to scan. Defaults to the current session region.

.PARAMETER ProfileName
    AWS credential profile name. Defaults to the current session profile.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.PARAMETER DatabasePorts
    Array of port numbers considered database ports. Defaults to common DB ports:
    1433 (MSSQL), 1521 (Oracle), 3306 (MySQL/MariaDB), 5432 (PostgreSQL),
    5439 (Redshift), 6379 (Redis), 27017 (MongoDB).

.NOTES
    Dependencies:
    - AWS.Tools.EC2 or AWSPowerShell

.EXAMPLE
    PS> Find-CHAREC2DBSG.ps1
    Lists all security groups allowing inbound DB connections on default ports.

.EXAMPLE
    PS> Find-CHAREC2DBSG.ps1 -DatabasePorts 3306, 5432
    Checks only MySQL and PostgreSQL ports.

.EXAMPLE
    PS> Find-CHAREC2DBSG.ps1 -Region us-west-2
    Scans security groups in us-west-2.
#>

function Find-CHAREC2DBSG {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int[]]$DatabasePorts = @(1433, 1521, 3306, 5432, 5439, 6379, 27017),

        # AWS common parameters
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        $null = Test-CHARAWSCmdlet -Name 'Get-EC2SecurityGroup'

        $portLabels = @{
            1433  = 'MSSQL'
            1521  = 'Oracle'
            3306  = 'MySQL/MariaDB'
            5432  = 'PostgreSQL'
            5439  = 'Redshift'
            6379  = 'Redis'
            27017 = 'MongoDB'
        }

        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
    }

    process {
        try {
            $securityGroups = Get-EC2SecurityGroup @awsParams

            if (-not $securityGroups) {
                Write-Output "No security groups found."
                return
            }

            $results = @()

            foreach ($sg in $securityGroups) {
                foreach ($rule in $sg.IpPermissions) {
                    # Check if this rule covers any database port
                    $matchedPorts = @()

                    foreach ($dbPort in $DatabasePorts) {
                        $isMatch = $false

                        if ($rule.IpProtocol -eq '-1') {
                            # All traffic rule covers all ports
                            $isMatch = $true
                        }
                        elseif ($rule.FromPort -le $dbPort -and $rule.ToPort -ge $dbPort) {
                            $isMatch = $true
                        }

                        if ($isMatch) {
                            $label = if ($portLabels.ContainsKey($dbPort)) { "$dbPort ($($portLabels[$dbPort]))" } else { "$dbPort" }
                            $matchedPorts += $label
                        }
                    }

                    if ($matchedPorts.Count -eq 0) {
                        continue
                    }

                    # Collect source CIDRs
                    $sources = @()
                    foreach ($ipRange in $rule.Ipv4Ranges) {
                        $sources += $ipRange.CidrIp
                    }
                    foreach ($ipv6Range in $rule.Ipv6Ranges) {
                        $sources += $ipv6Range.CidrIpv6
                    }

                    if ($sources.Count -eq 0) {
                        continue
                    }

                    $results += [PSCustomObject]@{
                        GroupId      = $sg.GroupId
                        GroupName    = $sg.GroupName
                        VpcId        = $sg.VpcId
                        Protocol     = if ($rule.IpProtocol -eq '-1') { 'All' } else { $rule.IpProtocol }
                        MatchedPorts = ($matchedPorts | Sort-Object -Unique) -join ', '
                        SourceCIDRs  = ($sources) -join ', '
                    }
                }
            }

            if ($results.Count -eq 0) {
                Write-Output "No security groups with inbound database port rules found."
                return
            }

            $results | Sort-Object GroupId
        }
        catch {
            Write-Error "Error in $($MyInvocation.MyCommand.Name): $_"
            throw
        }
    }
}


<#
.SYNOPSIS
    Count of EC2 related objects within a region.

.DESCRIPTION
    Returns count of Instances, Volumes, Snapshots, AutoScaling groups,
    and Load Balancers for one or more regions.

.PARAMETER Region
    Region or list of regions to scan. If not provided, scans all regions.

.PARAMETER ProfileName
    AWS credential profile name. Defaults to the current session profile.

.PARAMETER AccessKey
    The AWS access key for authentication.

.PARAMETER SecretKey
    The AWS secret key for authentication.

.PARAMETER SessionToken
    The AWS session token for temporary credentials.

.PARAMETER Credential
    An AWSCredentials object for authentication.

.PARAMETER ProfileLocation
    The location of the credentials file to use.

.PARAMETER EndpointUrl
    A custom endpoint URL to use for the AWS service.

.EXAMPLE
    PS C:\> .\Get-CHAREC2Count.ps1 | Format-Table

.EXAMPLE
    PS C:\> .\Get-CHAREC2Count.ps1 -Region us-east-1, us-west-2 -ProfileName MyProfile
#>
function Get-CHAREC2Count {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Region,

        # AWS common parameters
        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [string]$AccessKey,

        [Parameter()]
        [string]$SecretKey,

        [Parameter()]
        [string]$SessionToken,

        [Parameter()]
        [SecureString] $Credential,

        [Parameter()]
        [string]$ProfileLocation,

        [Parameter()]
        [string]$EndpointUrl
    )

    begin {
        @(
            'Get-EC2Region',
            'Get-ASAutoScalingGroup',
            'Get-ELB2LoadBalancer',
            'Get-ELBLoadBalancer'
        ) | Test-CHARAWSCmdlet | Out-Null

        # Build base AWS params (excludes Region since we iterate over regions)
        $baseAwsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters
        $baseAwsParams.Remove('Region') | Out-Null

        # Resolve regions if not provided
        if (-not $Region) {
            $Region = (Get-EC2Region @baseAwsParams).RegionName
        }
    }

    process {
        $output = @()
        $totalRegions = $Region.Count
        $currentIndex = 0

        foreach ($R in $Region) {
            $currentIndex++
            $percentComplete = [math]::Round(($currentIndex / $totalRegions) * 100)
            Write-Progress -Activity 'Scanning EC2 Resources' -Status "Region: $R ($currentIndex of $totalRegions)" -PercentComplete $percentComplete
            Write-Verbose "Region: $R"

            # Region-specific splat (adds Region to the base awsParams)
            $regionParams = $baseAwsParams.Clone()
            $regionParams['Region'] = $R

            try {
                $RegionData = [PSCustomObject][ordered]@{
                    Region                = $R
                    InstanceCount         = @(Get-EC2Instance @regionParams).Count
                    VolumeCount           = @(Get-EC2Volume @regionParams).Count
                    VolCapacityInGb       = (Get-EC2Volume @regionParams | Measure-Object -Property Size -Sum).Sum
                    SnapshotCount         = @(Get-EC2Snapshot -OwnerId self @regionParams).Count
                    AutoScalingGroupCount = @(Get-ASAutoScalingGroup @regionParams).Count
                    LoadBalancerCount     = @(Get-ELB2LoadBalancer @regionParams).Count + @(Get-ELBLoadBalancer @regionParams).Count
                    ScanOk                = $true
                }
                Write-Verbose "$RegionData"
            }
            catch {
                Write-Verbose "catch: $R - $_"
                $RegionData = [PSCustomObject][ordered]@{
                    Region                = $R
                    InstanceCount         = ''
                    VolumeCount           = ''
                    VolCapacityInGb       = ''
                    SnapshotCount         = ''
                    AutoScalingGroupCount = ''
                    LoadBalancerCount     = ''
                    ScanOk                = $false
                }
            }
            finally {
                $output += $RegionData
            }
        }

        Write-Progress -Activity 'Scanning EC2 Resources' -Completed
        return $output
    }
}



# ================================================================================================
# Get-CHARAllEC2Patch Function
# ================================================================================================

function Get-CHARAllEC2Patch {
    <#
    .SYNOPSIS
        Retrieves patch compliance data for all EC2 instances.

    .DESCRIPTION
        Queries all EC2 instances in the target account/region, retrieves their SSM patch
        compliance state, and returns patch objects. Supports AWS common credential and
        region parameters via splatting for multi-account/region usage.

        Includes exponential backoff retry logic for API throttling.

    .PARAMETER Region
        The AWS region to query. Falls back to the default region if not specified.

    .PARAMETER ProfileName
        The AWS credential profile name to use.

    .PARAMETER AccessKey
        The AWS access key for explicit credentials.

    .PARAMETER SecretKey
        The AWS secret key for explicit credentials.

    .PARAMETER SessionToken
        The session token for temporary session-based credentials.

    .PARAMETER Credential
        An AWSCredentials object instance.

    .PARAMETER NetworkCredential
        Used with SAML-based authentication when ProfileName references a SAML role profile.

    .PARAMETER ProfileLocation
        The path to the ini-format credential file.

    .PARAMETER EndpointUrl
        The endpoint to make the call against.

    .EXAMPLE
        Get-CHARAllEC2Patch -ProfileName 'production' -Region 'us-east-1'

        Retrieves patch data for all instances in the production account, us-east-1.

    .EXAMPLE
        Get-CHARAllEC2Patch -AccessKey $ak -SecretKey $sk -SessionToken $st -Region 'eu-west-1'

        Retrieves patch data using explicit temporary credentials.

    .EXAMPLE
        Get-CHARAllEC2Patch -Region 'us-east-1' | Export-Csv -Path 'patches.csv' -NoTypeInformation

        Exports patch compliance report to CSV.

    .NOTES
        Generated by Kiro using Auto, reviewed by ccharland
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Credential',
        Justification = 'Credential parameter accepts AWSCredentials object, not a password')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'NetworkCredential',
        Justification = 'NetworkCredential typed as [object] for pipeline compatibility')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$Region,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ProfileName,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$AccessKey,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SecretKey,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$SessionToken,

        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$Credential,

        [Parameter(ValueFromPipelineByPropertyName)]
        [object]$NetworkCredential,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ProfileLocation,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$EndpointUrl
    )

    begin {
        @(
            'Get-EC2Instance',
            'Get-SSMInstancePatch'
        ) | Test-CHARAWSCmdlet | Out-Null

        # Build AWS credential/region splat from bound parameters
        $awsParams = New-AWSParamSplat -BoundParameters $PSBoundParameters

        $UTCDate = Get-Date | Get-Date -Format "yyyy-MM-ddTHH:mm:ss"
        $report = New-Object System.Collections.ArrayList
    }

    process {
        $instances = (Get-EC2Instance @awsParams).Instances.InstanceId
        Write-Verbose "Found $($instances.Count) instances"
        foreach ($id in $instances) {
            $patches = $null
            $retryCount = 0
            $maxRetries = 5
            $baseDelay = 2
            Write-Verbose "Starting Get-SSMInstancePatch for $id"
            while ($retryCount -lt $maxRetries) {
                try {
                    $patches = @(Get-SSMInstancePatch -InstanceId $id @awsParams -ErrorAction Stop)
                    break
                }
                catch {
                    if ($_.Exception.Message -match "Rate exceeded|Throttling") {
                        $retryCount++
                        if ($retryCount -ge $maxRetries) {
                            Write-Warning "Failed to get patches for $id after $maxRetries retries. Skipping."
                            break
                        }
                        $delay = $baseDelay * [Math]::Pow(2, $retryCount - 1) + (Get-Random -Minimum 0 -Maximum 1000) / 1000
                        Write-Verbose "Rate limited on $id, retry $retryCount/$maxRetries in $([Math]::Round($delay, 1))s..."
                        Start-Sleep -Seconds $delay
                    }
                    else {
                        Write-Warning "Error getting patches for ${id}: $($_.Exception.Message). Skipping."
                        break
                    }
                }
            }

            if (-not $patches -or $patches.Count -eq 0) {
                Write-Verbose "No patches seen for $id"
                continue
            }

            Write-Information -MessageData "Instance $id has $($patches.Count) patches" -Tags "Summary"

            foreach ($p in $patches) {
                $newitem = [PSCustomObject]@{
                    ReportTime     = $UTCDate
                    InstanceId     = $id
                    Title          = $p.Title
                    KBId           = $p.KBId
                    State          = $p.State
                    Classification = $p.Classification
                    Severity       = $p.Severity
                    InstalledTime  = $p.InstalledTime
                }
                [void]$report.Add($newitem)
            }
        }
    }

    end {
        $report
    }
}



# ================================================================================================
# Module Exports
# ================================================================================================

# Export all functions
Export-ModuleMember -Function @(
    'Find-CHAREC2DBSG',
    'Find-CHAROpenSecurityGroup',
    'Get-CHARAllEC2Patch',
    'Get-CHAREC2Count',
    'Get-CHAREC2KeyTagNameStatus',
    'Get-CHAREC2SGInUse',
    'Get-CHAREC2SnapshotReport',
    'Get-CHAREC2VolumeReport',
    'Get-CHARGlobalAuditReportItem',
    'Get-CHARIAMAuditList',
    'Out-CHARAWSNetworkingComponent',
    'Out-CHARAWSSupportingInfo',
    'Start-CHAREC2RetryLoop'
)

# SIG # Begin signature block
# MIIgygYJKoZIhvcNAQcCoIIguzCCILcCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBtz9pCe9FukQE6
# kAlrMCfmyJUHsraMoK16mYy+BGmWpqCCG1gwggN5MIIC/qADAgECAhAcz51nzeIZ
# /xLZmv82guWnMAoGCCqGSM49BAMDMHwxCzAJBgNVBAYTAlVTMQ4wDAYDVQQIDAVU
# ZXhhczEQMA4GA1UEBwwHSG91c3RvbjEYMBYGA1UECgwPU1NMIENvcnBvcmF0aW9u
# MTEwLwYDVQQDDChTU0wuY29tIFJvb3QgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkg
# RUNDMB4XDTE5MDMwNzE5MzU0N1oXDTM0MDMwMzE5MzU0N1oweDELMAkGA1UEBhMC
# VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhT
# U0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRp
# YXRlIENBIEVDQyBSMjB2MBAGByqGSM49AgEGBSuBBAAiA2IABOpt7gyJbfdl1TyX
# rJy6JZGueJwq39d2z/FOJTbnNRuYrlS823MWKvLp+ziKPRCumlXWYiCS5X0xZxWv
# 2FIxsD9Tf7tCm8JcqSsa6W8uRyjXT+yEBglVRcOJGZiIjeFxJKOCAUcwggFDMBIG
# A1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh
# 6M0weAYIKwYBBQUHAQEEbDBqMEYGCCsGAQUFBzAChjpodHRwOi8vd3d3LnNzbC5j
# b20vcmVwb3NpdG9yeS9TU0xjb20tUm9vdENBLUVDQy0zODQtUjEuY3J0MCAGCCsG
# AQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNvbTARBgNVHSAECjAIMAYGBFUdIAAw
# EwYDVR0lBAwwCgYIKwYBBQUHAwMwOwYDVR0fBDQwMjAwoC6gLIYqaHR0cDovL2Ny
# bHMuc3NsLmNvbS9zc2wuY29tLWVjYy1Sb290Q0EuY3JsMB0GA1UdDgQWBBQyeLEO
# kNtGzxrPtmMRbf4w52dUMDAOBgNVHQ8BAf8EBAMCAYYwCgYIKoZIzj0EAwMDaQAw
# ZgIxAIZwNaUUH2Oi1OfK9PES0J4Ay3EIm1mAOjpxEHItL3pSmV+5tJ/iQQqK2Dwg
# evkxFQIxAIHLuf6CWo8Wvxn2XZR/+3do0Q/XjqQSbfhJlqwRUVPlxUz5aK1vpJwv
# LRHaPzhzXTCCA8AwggNHoAMCAQICEFEd7vPtDKtYV7OYcsTNL88wCgYIKoZIzj0E
# AwMweDELMAkGA1UEBhMCVVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3Vz
# dG9uMREwDwYDVQQKDAhTU0wgQ29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNp
# Z25pbmcgSW50ZXJtZWRpYXRlIENBIEVDQyBSMjAeFw0yNjA4MDcxOTA3NTdaFw0y
# NzExMDgxOTA3NTdaMHkxCzAJBgNVBAYTAlVTMRYwFAYDVQQIDA1OZXcgSGFtcHNo
# aXJlMRQwEgYDVQQHDAtOZXcgSXBzd2ljaDEdMBsGA1UECgwUQ2hyaXN0b3BoZXIg
# Q2hhcmxhbmQxHTAbBgNVBAMMFENocmlzdG9waGVyIENoYXJsYW5kMHYwEAYHKoZI
# zj0CAQYFK4EEACIDYgAEnBTifag8qbU07/B2aFtw7h3deXWsME/+F18vvlqQOnQg
# 5YNQyYRisw1XkwtXq2m1AMiqAddMEVOkmxIi71eYqVi87p/RQct3k/HuXi/clk4C
# YqaYFCEpq7tFMUDd8cUCo4IBkzCCAY8wDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAW
# gBQyeLEOkNtGzxrPtmMRbf4w52dUMDB5BggrBgEFBQcBAQRtMGswRwYIKwYBBQUH
# MAKGO2h0dHA6Ly9jZXJ0LnNzbC5jb20vU1NMY29tLVN1YkNBLWNvZGVTaWduaW5n
# LUVDQy0zODQtUjIuY2VyMCAGCCsGAQUFBzABhhRodHRwOi8vb2NzcHMuc3NsLmNv
# bTBRBgNVHSAESjBIMAgGBmeBDAEEATA8BgwrBgEEAYKpMAEDAwEwLDAqBggrBgEF
# BQcCARYeaHR0cHM6Ly93d3cuc3NsLmNvbS9yZXBvc2l0b3J5MBMGA1UdJQQMMAoG
# CCsGAQUFBwMDMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmxzLnNzbC5jb20v
# U1NMY29tLVN1YkNBLWNvZGVTaWduaW5nLUVDQy0zODQtUjIuY3JsMB0GA1UdDgQW
# BBRaKfdK1zqVgfdqPHp69Ump7V7QDjAOBgNVHQ8BAf8EBAMCB4AwCgYIKoZIzj0E
# AwMDZwAwZAIwfyXRtBRHbkmoEP6vHjnUe6Xb6WUcfzZ+r2mFqz3pxpokqXkdYfbn
# ySinlBy2oScEAjAmFdwaA7/yG/M+bPD8UviQ9p13KC3R2X1eXbRlCoRwLwdKSF89
# FQPG4jtmL9FPIawwggaCMIIEaqADAgECAhA2wrC9fBs656Oz3TbLyXVoMA0GCSqG
# SIb3DQEBDAUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKTmV3IEplcnNleTEU
# MBIGA1UEBxMLSmVyc2V5IENpdHkxHjAcBgNVBAoTFVRoZSBVU0VSVFJVU1QgTmV0
# d29yazEuMCwGA1UEAxMlVVNFUlRydXN0IFJTQSBDZXJ0aWZpY2F0aW9uIEF1dGhv
# cml0eTAeFw0yMTAzMjIwMDAwMDBaFw0zODAxMTgyMzU5NTlaMFcxCzAJBgNVBAYT
# AkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNVBAMTJVNlY3RpZ28g
# UHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCIndi5RWedHd3ouSaBmlRUwHxJBZvMWhUP2ZQQRLRBQIF3
# FJmp1OR2LMgIU14g0JIlL6VXWKmdbmKGRDILRxEtZdQnOh2qmcxGzjqemIk8et8s
# E6J+N+Gl1cnZocew8eCAawKLu4TRrCoqCAT8uRjDeypoGJrruH/drCio28aqIVEn
# 45NZiZQI7YYBex48eL78lQ0BrHeSmqy1uXe9xN04aG0pKG9ki+PC6VEfzutu6Q3I
# cZZfm00r9YAEp/4aeiLhyaKxLuhKKaAdQjRaf/h6U13jQEV1JnUTCm511n5avv4N
# +jSVwd+Wb8UMOs4netapq5Q/yGyiQOgjsP/JRUj0MAT9YrcmXcLgsrAimfWY3MzK
# m1HCxcquinTqbs1Q0d2VMMQyi9cAgMYC9jKc+3mW62/yVl4jnDcw6ULJsBkOkrcP
# LUwqj7poS0T2+2JMzPP+jZ1h90/QpZnBkhdtixMiWDVgh60KmLmzXiqJc6lGwqoU
# qpq/1HVHm+Pc2B6+wCy/GwCcjw5rmzajLbmqGygEgaj/OLoanEWP6Y52Hflef3XL
# vYnhEY4kSirMQhtberRvaI+5YsD3XVxHGBjlIli5u+NrLedIxsE88WzKXqZjj9Zi
# 5ybJL2WjeXuOTbswB7XjkZbErg7ebeAQUQiS/uRGZ58NHs57ZPUfECcgJC+v2wID
# AQABo4IBFjCCARIwHwYDVR0jBBgwFoAUU3m/WqorSs9UgOHYm8Cd8rIDZsswHQYD
# VR0OBBYEFPZ3at0//QET/xahbIICL9AKPRQlMA4GA1UdDwEB/wQEAwIBhjAPBgNV
# HRMBAf8EBTADAQH/MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBEGA1UdIAQKMAgwBgYE
# VR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20v
# VVNFUlRydXN0UlNBQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYIKwYBBQUH
# AQEEKTAnMCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3QuY29tMA0G
# CSqGSIb3DQEBDAUAA4ICAQAOvmVB7WhEuOWhxdQRh+S3OyWM637ayBeR7djxQ8Si
# hTnLf2sABFoB0DFR6JfWS0snf6WDG2gtCGflwVvcYXZJJlFfym1Doi+4PfDP8s0c
# qlDmdfyGOwMtGGzJ4iImyaz3IBae91g50QyrVbrUoT0mUGQHbRcF57olpfHhQESt
# z5i6hJvVLFV/ueQ21SM99zG4W2tB1ExGL98idX8ChsTwbD/zIExAopoe3l6JrzJt
# Pxj8V9rocAnLP2C8Q5wXVVZcbw4x4ztXLsGzqZIiRh5i111TW7HV1AtsQa6vXy63
# 3vCAbAOIaKcLAo/IU7sClyZUk62XD0VUnHD+YvVNvIGezjM6CRpcWed/ODiptK+e
# vDKPU2K6synimYBaNH49v9Ih24+eYXNtI38byt5kIvh+8aW88WThRpv8lUJKaPn3
# 7+YHYafob9Rg7LyTrSYpyZoBmwRWSE4W6iPjB7wJjJpH29308ZkpKKdpkiS9WNsf
# /eeUtvRrtIEiSJHN899L1P4l6zKVsdrUu1FX1T/ubSrsxrYJD+3f3aKg6yxdbugo
# t06YwGXXiy5UUGZvOu3lXlxA+fC13dQ5OlL2gIb5lmF6Ii8+CQOYDwXM+yd9dbmo
# cQsHjcRPsccUd5E9FiswEqORvz8g3s+jR3SFCgXhN4wz7NgAnOgpCdUo4uDyllU9
# PzCCBqcwggSPoAMCAQICEQCQrAhyIP3Fp8RrXMcN9z0GMA0GCSqGSIb3DQEBDAUA
# MFcxCzAJBgNVBAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLjAsBgNV
# BAMTJVNlY3RpZ28gUHVibGljIFRpbWUgU3RhbXBpbmcgUm9vdCBSNDYwHhcNMjYw
# MzI1MDAwMDAwWhcNNDEwMzI0MjM1OTU5WjBVMQswCQYDVQQGEwJHQjEYMBYGA1UE
# ChMPU2VjdGlnbyBMaW1pdGVkMSwwKgYDVQQDEyNTZWN0aWdvIFB1YmxpYyBUaW1l
# IFN0YW1waW5nIENBIFI0MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AK7kSqIBrYIcYvlmLVuaA8zw1RfBhkn4G1CoemzjcYtML6yNUvKmwGH7y6/5MuSC
# 1UYP/+9KYDSqvMQt/1hEKHYxMAD9oZpBkoaDQFEKbOJHelsKe+BaO0ZcENTKfePc
# raVkA7wrGAW2XHA5gQCQv4IKori/3PNOXxnDMOk8yIMgVrlMeTxqfWJ4XkjT1xc2
# s9DD7URHWWJOFobTPoWs6mrDFlaY9FlAHDYTfbzvxQHVsvRmn3W+5ZmCwyk02I8K
# gGPT/UX4sTz41GiR+ppwUjQXa1+2tEHZbsdAKUtH3OPEVtZvlt7atx4h83IdRR8o
# Yi8wjY3OjFKXFecWpQbzzsPxbUKPwMWiTrzwkrFa8dH/1pDKRJt371W62PfqKPay
# Cr/XbnBOlRn8CALSmHnRtGzuAWtTJpcT3BKw6oy8IIL6wSbu938F6ZIbRNIc1dKb
# IJtr4ULN6R5ZfTdNEhwXctqp3RHDbg4fuOl6LjNoaFwjud92EEDhzxFJzE1jqN4c
# sceZIwxOT1aqfsfh0uFQE/lgTBuBs3i6/WL2W1OceWLy3XEdXRK1f0EWCuea6dNf
# X2RRdjUfk5EltFnJkN2+bWhnK14OPRKcyjOv5hKZ0iV4NRNd1+hjtva1rPyzb5Bs
# 7EvFxqEQhgZbOq7qH3nm0rBwA0dxniBOYCFPdu246JCxAgMBAAGjggFuMIIBajAf
# BgNVHSMEGDAWgBT2d2rdP/0BE/8WoWyCAi/QCj0UJTAdBgNVHQ4EFgQUOnSlDGfG
# QlDC/bX8x7spNIL0erkwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwEwYDVR0lBAwwCgYIKwYBBQUHAwgwIwYDVR0gBBwwGjAIBgZngQwBBAIwDgYM
# KwYBBAGyMQECAQMIMEwGA1UdHwRFMEMwQaA/oD2GO2h0dHA6Ly9jcmwuc2VjdGln
# by5jb20vU2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ1Jvb3RSNDYuY3JsMHwGCCsG
# AQUFBwEBBHAwbjBHBggrBgEFBQcwAoY7aHR0cDovL2NydC5zZWN0aWdvLmNvbS9T
# ZWN0aWdvUHVibGljVGltZVN0YW1waW5nUm9vdFI0Ni5wN2MwIwYIKwYBBQUHMAGG
# F2h0dHA6Ly9vY3NwLnNlY3RpZ28uY29tMA0GCSqGSIb3DQEBDAUAA4ICAQAy3lJH
# ZvGeA2b43yhzoarvobHVzbfl+RfuPDwej0wCQkYAN6scTt2GwFe22qbOCv/tllqF
# lLKQZE+E9jVyuPTbyQHwrM7R0oLapAEDC1+CowsqSRf/ptira5Pfd4PoHICnb9co
# PQtyZmHSQp5y9IGvqWf1qNfq7V2fHZ8DvEQrLUzeoGF9BJRYu2OzacW3QQtUum3N
# OVf0gPRwv6I4991uhncJ6VP4lcpUpHZKB7R3hiIUC09mR9KjzPVnXHvL9n2bAwiU
# ECfK5Zezhiw27F2tgi39DETfU8M4n0N6xLgFzsf05M5GURX8C9+IX9V6kpmmKtrU
# zMti4LD66gtmf+mSm934K81NL6YQeMEk1rpYrWPypcW76Mir6wb1AgseLIHqn/Gk
# euQm7zOTDf3f5WoX14qVNjZWNHF3JxkutV6ZnhinfCLfdv5bnwKWUfceqOajCVnt
# I6uCbHxjBg6SCsexc5AfIGno7gVFvwifT4XONPsSUaJ71XsJ+EvciVUVnjOO4qxm
# 0fWJTd8a7jP8mc4ZPqwJvQFtOp7+6G+kUJAF0fnE8YgD8uttBReNTa1YmAeFMiqc
# 38e8fI4eLm0zjM/eeGCHasnoqqrbGwcF41iz9HXzFDwN4iD5z3QShp6HRiU3UpTw
# DJiiXcr0z6pjl7PyzJ3/tmWtGehV7CAfc/WlyzCCBuIwggTKoAMCAQICEQDnTvJV
# sFBP+tum3/f8i6MVMA0GCSqGSIb3DQEBDAUAMFUxCzAJBgNVBAYTAkdCMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgQ0EgUjQxMB4XDTI2MDMyNTAwMDAwMFoXDTM3MDYyNDIzNTk1
# OVowcjELMAkGA1UEBhMCR0IxFzAVBgNVBAgTDkdyZWF0ZXIgTG9uZG9uMRgwFgYD
# VQQKEw9TZWN0aWdvIExpbWl0ZWQxMDAuBgNVBAMTJ1NlY3RpZ28gUHVibGljIFRp
# bWUgU3RhbXBpbmcgU2lnbmVyIFIzNzCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCC
# AgoCggIBALL/w21L3FDZRS0FEXfZuPtUrefibnRSqOT/NNyJLOJhXjQfUspqHT+g
# SSVgbjYThUI/cO+wFQHoOakKQNnSMKdkE8gR69ofXlkk5DAVY/ZlevliOUmlvrw2
# Vuz4SU28rHfb/Vgd17eqpRIvJuO6XE8vPpPzn4c4iorszUF6nwuynKEQ/+rqfDmQ
# bFNKsa+5+Z4f4kXwKdUFxUwUDjQWUhiHRwMlUWGF9N91aAvL+9a4sxCgqR/ez8W8
# HJ/XqvSu1vIeb+J6bDFKKgkv3PJkMMpQ0BsdeXR2FejZXFRXY1w9dZe6gqyMv7px
# +TpWbYMefECUV0WxoEMgXUk6RKcLo94uUHOdmfZu4Xe8ghglyro3/N4VEKTj8dcP
# PvOBGxFEx1QH6uHKTkWhloGPDScurcZnd8KUtTHl6zmlQDHM04MwGfsmQViKnYEA
# YE8RHl5XRE6GTq0ZMb59SIyJX6+CODVic/kW+dhbIS1Z5AP8HaGne/PRG+12QzSn
# eKDJp3Ot+k4GrmmlWT9iy6FNCQ/32K+d4cAZ+Ll7uWbEn6Z6gE+tEu7MyZvzWvPN
# sRKMkcyyflFW1zpRyzutwypALXc9Qg7sFsYERNXa58KZXqU9Onc/tck6+adQJFM9
# tW8xOnE//P5I4eDj84IGGKqzgUD37ihC+WST3DfY0YBKWL0ZaubnAgMBAAGjggGO
# MIIBijAfBgNVHSMEGDAWgBQ6dKUMZ8ZCUML9tfzHuyk0gvR6uTAdBgNVHQ4EFgQU
# YRDpehKvUcSF1PLPpHQPUM0gr/gwDgYDVR0PAQH/BAQDAgbAMAwGA1UdEwEB/wQC
# MAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwSgYDVR0gBEMwQTAIBgZngQwBBAIw
# NQYMKwYBBAGyMQECAQMIMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5j
# b20vQ1BTMEoGA1UdHwRDMEEwP6A9oDuGOWh0dHA6Ly9jcmwuc2VjdGlnby5jb20v
# U2VjdGlnb1B1YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNybDB6BggrBgEFBQcBAQRu
# MGwwRQYIKwYBBQUHMAKGOWh0dHA6Ly9jcnQuc2VjdGlnby5jb20vU2VjdGlnb1B1
# YmxpY1RpbWVTdGFtcGluZ0NBUjQxLmNydDAjBggrBgEFBQcwAYYXaHR0cDovL29j
# c3Auc2VjdGlnby5jb20wDQYJKoZIhvcNAQEMBQADggIBAAPqPY3RrM36GXqTpsoH
# n9TpW5I6z3dkFvc9zPL1W0Egq7j3jtnkbAvRoWeAjGX4ZK4sWsmA+u4EJG8okQmy
# buS/4tDUI5UIQb21n4hG2vihxShrneWB0VoQ2VLQ3jCCRmRtAQ+/7H7WVKNiH5Pg
# l4v2ZTOdPsStzpKnl1YuRrmww/+bcZmLqgk909ywIpZqAfubYfbEMYjIckLk90f2
# mG+L8qaGSS2JJVM02pV5XltZ1fbOFETpRN/PQhwygIv33qUUjJ1fE4ITgw0McMzR
# qziWdOJP8ocxxw7qXxz1OdRWCalyL1qvUgAFnZTVdSRiMYZKf0wLcQcM/1Xf1W4F
# W9nff8ERX8RZJGt/TtPuMWmUpf6BCv9Q6o8YyUTtknvZRpSQ0nLttWXdtwsrN2mM
# gfMuR//gxVrVXvDzCoK/lbiA6dEZOW53lQwBFtEzwE/FH8JdhegyYg4PymZOTZrG
# BEvgsbxe25yEhJ0IdGa1pwCYsarldJhJVMdNcAOU7jyIMqHcczav3wtIXp/SwbXZ
# 3xX0mfsLfANSJ47G4qPgx1atb6GIlTaQXzu/p4fTQeAIUVzZXT4K984IyfuO7NLj
# WMtog1wGUpZD98pv+4Mt9Y5bvfPUjaUVjtePy1DVdi0rl5ESNYi0zyOmXVxtA5zz
# xu1H7RdLZOZugT/XjX69rY9bMYIEyDCCBMQCAQEwgYwweDELMAkGA1UEBhMCVVMx
# DjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMREwDwYDVQQKDAhTU0wg
# Q29ycDE0MDIGA1UEAwwrU1NMLmNvbSBDb2RlIFNpZ25pbmcgSW50ZXJtZWRpYXRl
# IENBIEVDQyBSMgIQUR3u8+0Mq1hXs5hyxM0vzzANBglghkgBZQMEAgEFAKCBhDAY
# BgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3DQEJBDEi
# BCDOU2JYA0xv/ReWjZ6CoOxMZ96AnJe/ve1/vQDH6SuiKDALBgcqhkjOPQIBBQAE
# ZjBkAjB9++rheoq556T+IXXIUl7PHjBAgvvftxx74a/FfdafNtwSehI9oJ48cD38
# GMF7VkICMFKznuMo0R6cryMRWjrOXtdfYcb2Jy6WBefABaGvD+kA768EG40v1n6a
# G7uVf0vAJqGCAyMwggMfBgkqhkiG9w0BCQYxggMQMIIDDAIBATBqMFUxCzAJBgNV
# BAYTAkdCMRgwFgYDVQQKEw9TZWN0aWdvIExpbWl0ZWQxLDAqBgNVBAMTI1NlY3Rp
# Z28gUHVibGljIFRpbWUgU3RhbXBpbmcgQ0EgUjQxAhEA507yVbBQT/rbpt/3/Iuj
# FTANBglghkgBZQMEAgIFAKB5MBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJ
# KoZIhvcNAQkFMQ8XDTI2MDgyMzIxMTMxMVowPwYJKoZIhvcNAQkEMTIEMF5aKKGb
# IUQNZ/xgE1vWCwHrky3HadJfWyb/AB7f8cB5IcFXWcyjSda3mvly3fL0YTANBgkq
# hkiG9w0BAQEFAASCAgAtLGJUCaHN1PZcqQmJ4E3XD3kia6qJIC3Ng5xSpsJ0vLSR
# Rwp4w/z007EcMzANuSbG9GramdmH5BI9QJHErhNEp8s9CwGjAbuvGL6+3Y7Cqs4l
# SioILGBdDcB1eXFZ0eTZBsXw2l3G4fO9LbJbZuTmiWT2jB7HCsBFplTczpDU24UL
# Oeb9xvMFYI5Pl8IPcRVRC3P/lIuHYIGXFbJmh2jZ+LQz7PEau9tLyP7Wb8UKGs0T
# M+gkjIM0dNQDx2j0r5WQv/LP8Wj5ebI8ncDC8iQjHBbS31BWwp8hxshGViArUdNO
# bEpkyus68LsFvbN1vfIHR3pnzXNXJ7pWGQ5tDMoEsrr3WgpAPPMfkTks01JGHrdK
# QF9W4ANglIuaPHH2yASNVEUuZ575YPjYCctuPycikID7hcuCdMSyf+3Aylr4KRsh
# GBG15EIdqHWtQqOk921LeFdt7L2xs054+hDucx49grYUE2KjWVAXTQdGJFisxqM9
# zbkT2sv2MKc2Mmx4P5c4sElNAbHsmrk5Drf95zQvjZzq2/THKu/Oa1U/coDaUzhO
# 3/AbxVOWem9u2V2Yc4nYMl2VLaV6sgnM20UTQyGZPE5rQjeAvM71Yq8Anb9wGa0r
# 6dRNYOe4YNyoHtrDRonY3ahscFx/5fMLwuLztybp3QVv27mEXZUWY8aSkv8vuQ==
# SIG # End signature block
