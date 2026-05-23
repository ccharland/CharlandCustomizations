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

# ================================================================================================
# Get-EC2SGInUse Function
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
    Get-EC2SGInUse
    # Gets all security groups in the default region and shows their associated resources.

.EXAMPLE
    Get-EC2SGInUse -Region us-west-2
    # Gets all security groups in the us-west-2 region and shows their associated resources.

.EXAMPLE
    Get-EC2SGInUse -GroupId sg-12345678
    # Gets the security group with the ID sg-12345678 and shows its associated resources.

.EXAMPLE
    Get-EC2SecurityGroup -GroupId sg-12345678 | Get-EC2SGInUse
    # Gets the security group with the ID sg-12345678 using the pipeline and shows its associated resources.

#>
function Get-EC2SGInUse {
    [CmdletBinding()]
    param (
        [string]$Region = ((Get-DefaultAWSRegion).Region),
        [string]$ProfileName,

        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$GroupId = @()
    )
    begin {
        $AwsParams = @{ Region = $Region }
        if ($ProfileName) { $AwsParams.ProfileName = $ProfileName }

        try {
            if ($GroupId.Count -eq 0) {
                Write-Verbose "No security groups specified. Getting all security groups in region $Region"
                Write-Progress -Activity 'Get Security Group List:' -Status 'In Progress'
                $GroupId = (Get-EC2SecurityGroup @AwsParams).GroupId
                if ($GroupId.Count -eq 0) {
                    throw "No security groups found in region $Region"
                }
            }
        }
        catch {
            throw "No security groups found in region $Region"
        }
        finally {
            Write-Progress -Activity 'Get Security Group List:' -Completed
        }

        Write-Progress -Activity 'Get Resource List:' -Status 'Instances'
        $InstancesMaster = Get-EC2Instance @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'NetworkInterfaces'
        $NetworkInterfaceMaster = Get-EC2NetworkInterface @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'LoadBalancer'
        $LoadBalancerMaster = Get-ELB2LoadBalancer @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'EndPoints'
        $EndPointsMaster = Get-EC2VPCEndpoint @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'Databases'
        $DatabasesMaster = Get-RDSDBInstance @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'ClientEndpoints'
        $VPNCLientEndpointMaster = Get-EC2ClientVpnEndpoint @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'Lambda'
        $LambdaFunctionsMaster = Get-LMFunctionList @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'ElasticCache'
        $ElastiCacheClustersMaster = Get-ECCacheCluster @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'MSK'
        $MSKClustersMaster = Get-MSKClusterList @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'Neptune'
        $NeptuneClustersMaster = Get-NPTDBCluster @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'MQBroker'
        $MQBrokersMaster = Get-MQBrokerList @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'FSX'
        $FSxFileSystemsMaster = Get-FSXFileSystem @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'Directory'
        $DirectoriesMaster = Get-DSDirectory @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'Workspace'
        $WorkSpacesMaster = Get-WKSWorkspace @AwsParams
        Write-Progress -Activity 'Get Resource List:' -Status 'SageMaker'

        try {
            $SageMakerNotebookInstanceListMaster = Get-SMNotebookInstanceList @AwsParams | ForEach-Object { Get-SMNotebookInstance @AwsParams }
        }
        catch {
            $SageMakerNotebookInstanceListMaster = $null
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
            $SecurityGroup = Get-EC2SecurityGroup @AwsParams -GroupId $SG
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
                $ClusterInfo = Get-MSKCluster -ClusterArn $_.ClusterArn -Region $Region
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
            $MQBrokers = $MQBrokersMaster | ForEach-Object { Get-MQBroker -Region $Region | Where-Object {
                    $_.SecurityGroups -contains $SG }
            }
            $UsedByCount += $MQBrokers.Count

            # Get associated FSx file systems
            $FSxFileSystems = $FSxFileSystemsMaster | Where-Object {
                $_.NetworkInterfaceIds | ForEach-Object {
                    $ENI = Get-EC2NetworkInterface -NetworkInterfaceId $_ -Region $Region
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
                $WorkspaceDetails = Get-WKSWorkspace -WorkspaceId $WorkspaceId -Region $Region
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
            }
        }
    }

    end {
        return $Results
    }
}

# ================================================================================================
# Out-AWSSupportingInfo Function
# ================================================================================================

function Out-AWSSupportingInfo {
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
        AWS profile name. Optional.
    .EXAMPLE
        Out-AWSSupportingInfo
    .EXAMPLE
        Out-AWSSupportingInfo -Region us-west-2 -RootPath C:\AWSInfo
    .OUTPUTS
        Creates files in <RootPath>/<AccountId>/<Region>/:
        - SSMParameters.txt
        - Secrets.txt (names only, not values)
        - CFNExports.txt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Region = ((Get-DefaultAWSRegion).Region),

        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        [Parameter()]
        [string]$ProfileName
    )

    $AwsParams = @{ Region = $Region }
    if ($ProfileName) { $AwsParams.ProfileName = $ProfileName }

    $AccountId = (Get-STSCallerIdentity @AwsParams).Account
    Write-Verbose "AccountId: $AccountId | Region: $Region"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $Region)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-SSMParameterList @AwsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'SSMParameters.txt') -Force

    Get-SECSecretList @AwsParams |
    Select-Object Name, Description |
    Out-File -FilePath (Join-Path $OutputDir 'Secrets.txt') -Force

    Get-CFNExport @AwsParams |
    Select-Object Name, Value |
    Out-File -FilePath (Join-Path $OutputDir 'CFNExports.txt') -Force

    Write-Output "Exported supporting info to: $OutputDir"
}

# ================================================================================================
# Out-AWSNetworkingComponent Function
# ================================================================================================

function Out-AWSNetworkingComponent {
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
        AWS profile name. Optional.
    .EXAMPLE
        Out-AWSNetworkingComponent
    .EXAMPLE
        Out-AWSNetworkingComponent -Region us-east-1 -RootPath C:\AWS
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
        [string]$Region = ((Get-DefaultAWSRegion).Region),

        [Parameter()]
        [string]$RootPath = (Get-Location).Path,

        [Parameter()]
        [string]$ProfileName
    )

    $AwsParams = @{ Region = $Region }
    if ($ProfileName) { $AwsParams.ProfileName = $ProfileName }

    $AccountId = (Get-STSCallerIdentity @AwsParams).Account
    Write-Verbose "AccountId: $AccountId | Region: $Region"

    $OutputDir = Join-Path -Path $RootPath -ChildPath (Join-Path -Path $AccountId -ChildPath $Region)
    if (-not (Test-Path -Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    Write-Verbose "Output directory: $OutputDir"

    Get-EC2VpnConnection @AwsParams |
    Select-Object VpnConnectionId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPNConnections.txt') -Force

    Get-EC2Vpc @AwsParams |
    Select-Object VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock,
    @{Name = 'AssociatedCidrBlocks'; Expression = { ($_.CidrBlockAssociationSet | ForEach-Object { $_.CidrBlock }) -join ', ' } } |
    Out-File -FilePath (Join-Path $OutputDir 'VPCs.txt') -Force

    Get-EC2Subnet @AwsParams |
    Select-Object VpcId, SubnetId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    CidrBlock, AvailabilityZone, AvailableIpAddressCount |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'Subnets.txt') -Force

    Get-EC2RouteTable @AwsParams |
    Select-Object RouteTableId, VpcId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } },
    @{Name = 'AssociationCount'; Expression = { ($_.Associations | Measure-Object).Count } } |
    Sort-Object VpcId |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'RouteTables.txt') -Force

    Get-EC2ManagedPrefixList @AwsParams |
    Format-Table PrefixListId, PrefixListName |
    Out-File -FilePath (Join-Path $OutputDir 'PrefixLists.txt') -Force

    Get-EC2TransitGatewayRouteTable @AwsParams |
    Select-Object TransitGatewayRouteTableId,
    @{Name = 'Name'; Expression = { ($_.Tags | Where-Object { $_.Key -eq 'Name' }).Value } } |
    Format-Table |
    Out-File -FilePath (Join-Path $OutputDir 'TransitGatewayRouteTables.txt') -Force

    Get-EC2TransitGatewayAttachment @AwsParams |
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
# Get-IAMAuditList Function
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

    PS> Get-IAMAuditList -ProfileName $profile-list  |out-file -Path '\reports\complete-credentails.csv'

.NOTES
    https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_getting-report.html?icmpid=docs_iam_help_panel#id_credentials_understanding_the_report_format
#>
function Get-IAMAuditList {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string[]]
        $ProfileName
    )

    begin {
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
# Get-GlobalAuditReportItem Function
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
    PS C:\> Get-GlobalAuditReportItem
    Gets a count of AWS resources in the default region (us-east-1)
.EXAMPLE
    PS C:\> Get-GlobalAuditReportItem -Region @("us-east-1", "us-west-2")
    Gets a count of AWS resources in multiple regions
.INPUTS
    String array of region names
.OUTPUTS
    PSCustomObject with resource counts by region
.NOTES
    General notes - this is a first version to get the basics in place
#>
function Get-GlobalAuditReportItem {
    [CmdletBinding()]
    param(
        [string[]]$Region = @('us-east-1'),
        [string]$ProfileName
    )

    $output = @()
    foreach ($RegionName in $Region) {
        $AwsParams = @{ Region = $RegionName }
        if ($ProfileName) { $AwsParams.ProfileName = $ProfileName }

        Write-Output $RegionName
        $RegionResults = New-Object -TypeName 'PSCustomObject' -Property @{
            account          = (Get-STSCallerIdentity @AwsParams).Account
            region           = $RegionName
            VMCount          = (Get-Ec2Instance @AwsParams).count
            CloudFront       = (Get-CFDistributionList @AwsParams).count
            LoadBalancer     = (Get-ELB2LoadBalancer @AwsParams).count + (Get-ELBLoadBalancer @AwsParams).count
            AutoScaling      = (Get-ASAutoScalingGroup @AwsParams).count
            RDS              = (Get-RDSDBInstance @AwsParams).count
            EFS              = (Get-EFSFileSystem @AwsParams).count
            ECS              = (Get-ECSClusterList @AwsParams).count
            EKS              = (Get-EKSClusterList @AwsParams).count
            KMS              = (Get-KMSKeyList @AwsParams).count
            Lambda           = (Get-LMFunctionList @AwsParams).count
            Certs            = (Get-ACMCertificateList @AwsParams).count
            Secrets          = (Get-SECSecretList @AwsParams).count
            DynamoDB         = (Get-DDBTableList @AwsParams).count
            RDS_Maria        = (Get-RDSDBInstance @AwsParams -filter @{name = 'engine'; values = 'mariadb' }).count
            Redshift         = (Get-RSCluster @AwsParams).count
            SNS_SQS          = (Get-SQSQueue @AwsParams).count + (Get-SNSTopic @AwsParams).count
            Step             = (Get-SFNStateMachineList @AwsParams).count
            DirectoryService = (Get-DSDirectory @AwsParams).count
            Forecast         = (Get-FRCForecastList @AwsParams).count
            StorageGateway   = (Get-SGGateway @AwsParams).count
        }

        $output += $RegionResults
    }
    return $output
}

# ================================================================================================
# Get-EC2KeyTagNameStatus Function
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

.OUTPUTS
PSobject
ResourceID, KeyPresent

.EXAMPLE
Get-EC2KeyTagNameStatus -TagKey "Name"
Checks if all EC2 resources have a "Name" tag
#>
function Get-EC2KeyTagNameStatus {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String]
        $TagKey,
        $taglist = $null,
        $filter = $null
    )

    if ($null -eq $taglist) {
        if ($filter) {
            $Taglist = get-EC2Tag -filter $filter | Group-Object resourceId
        }
        else {
            $Taglist = get-EC2Tag | Group-Object resourceId
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

# ================================================================================================
# Get-EC2SnapshotReport Function
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

.OUTPUTS
    PSCustomObject with the following properties:
    - SnapshotId: The snapshot identifier
    - VolumeId: The source volume identifier
    - StartTime: When the snapshot was initiated
    - Description: Snapshot description
    - State: Current snapshot state (pending, completed, error)
    - Tag:<TagName>: One dynamic property per tag on the snapshot

.EXAMPLE
    PS> Get-EC2SnapshotReport
    Returns all self-owned snapshots in the current region with default batch size.

.EXAMPLE
    PS> Get-EC2SnapshotReport -MaxResults 500 | Export-Csv -Path snapshots.csv -NoTypeInformation
    Exports all snapshots to CSV using larger batch size for fewer API calls.

.EXAMPLE
    PS> Get-EC2SnapshotReport | Where-Object { $_.State -eq 'completed' } | Measure-Object
    Counts all completed snapshots in the current region.

.NOTES
    Uses $AWSHistory.LastServiceResponse.NextToken for pagination.
    The -OwnerId 'self' filter ensures only account-owned snapshots are returned.
#>
function Get-EC2SnapshotReport {
    [CmdletBinding()]
    param(
        [int]$MaxResults = 200
    )

    $output = @()
    $NextToken = $null

    do {
        #process in smaller groups
        Write-Information -MessageData "Fetching info on up to $($MaxResults) snapshots"
        $SnapshotList = Get-EC2Snapshot -OwnerId self -NextToken $NextToken -maxresult $MaxResults
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

# ================================================================================================
# Get-EC2VolumeReport Function
# ================================================================================================

<#
.SYNOPSIS
    Gets a report of all EC2 volumes in the current region
.DESCRIPTION
    Lists all EC2 volumes and their attachment status, including unattached volumes
.EXAMPLE
    Get-EC2VolumeReport
    Gets all volumes in the current region
#>
function Get-EC2VolumeReport {
    [CmdletBinding()]
    param()

    $volist = Get-Ec2Volume
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

# ================================================================================================
# Start-EC2RetryLoop Function
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
    Start-EC2RetryLoop -ScriptBlock {Get-EC2Instance} -MaxRetries 5
#>
function Start-EC2RetryLoop {
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
# Find-OpenSecurityGroup Function
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

.PARAMETER AllowedPorts
    Ports that are acceptable to have open to the internet. Defaults to 80 and 443.

.EXAMPLE
    Find-OpenSecurityGroup
    Scans the current region for overly permissive security groups.

.EXAMPLE
    Find-OpenSecurityGroup -Region us-west-2 -AllowedPorts 80,443,8080
    Scans us-west-2, treating ports 80, 443, and 8080 as acceptable.
#>
function Find-OpenSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [int[]]$AllowedPorts = @(80, 443)
    )

    # Build common parameters for AWS calls
    $awsParams = @{}
    if ($Region) { $awsParams['Region'] = $Region }
    if ($ProfileName) { $awsParams['ProfileName'] = $ProfileName }

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

.PARAMETER DatabasePorts
    Array of port numbers considered database ports. Defaults to common DB ports:
    1433 (MSSQL), 1521 (Oracle), 3306 (MySQL/MariaDB), 5432 (PostgreSQL),
    5439 (Redshift), 6379 (Redis), 27017 (MongoDB).

.NOTES
    Dependencies:
    - AWS.Tools.EC2 or AWSPowerShell

.EXAMPLE
    PS> Find-EC2DBSG.ps1
    Lists all security groups allowing inbound DB connections on default ports.

.EXAMPLE
    PS> Find-EC2DBSG.ps1 -DatabasePorts 3306, 5432
    Checks only MySQL and PostgreSQL ports.

.EXAMPLE
    PS> Find-EC2DBSG.ps1 -Region us-west-2
    Scans security groups in us-west-2.
#>

function Find-EC2DBSG {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProfileName,

        [Parameter()]
        [int[]]$DatabasePorts = @(1433, 1521, 3306, 5432, 5439, 6379, 27017)
    )

    begin {
        $portLabels = @{
            1433  = 'MSSQL'
            1521  = 'Oracle'
            3306  = 'MySQL/MariaDB'
            5432  = 'PostgreSQL'
            5439  = 'Redshift'
            6379  = 'Redis'
            27017 = 'MongoDB'
        }

        # Build splat hash for AWS cmdlet calls
        $awsParams = @{}
        if ($Region) {
            $awsParams['Region'] = $Region
        }
        if ($ProfileName) {
            $awsParams['ProfileName'] = $ProfileName
        }
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

.EXAMPLE
    PS C:\> .\Get-EC2Count.ps1 | Format-Table

.EXAMPLE
    PS C:\> .\Get-EC2Count.ps1 -Region us-east-1, us-west-2 -ProfileName MyProfile
#>
function Get-EC2Count {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$Region,

        [Parameter()]
        [string]$ProfileName
    )

    begin {
        # Build splat hash for AWS cmdlet calls
        $awsParams = @{}
        if ($ProfileName) {
            $awsParams['ProfileName'] = $ProfileName
        }

        # Resolve regions if not provided
        if (-not $Region) {
            $Region = (Get-EC2Region @awsParams).RegionName
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
            $regionParams = $awsParams.Clone()
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
# Module Exports
# ================================================================================================

# Export all functions
Export-ModuleMember -Function @(
    'Get-EC2SGInUse',
    'Get-EC2Count',
    'Find-EC2DBSG',
    'Out-AWSSupportingInfo',
    'Out-AWSNetworkingComponent',
    'Get-IAMAuditList',
    'Get-GlobalAuditReportItem',
    'Get-EC2KeyTagNameStatus',
    'Get-EC2SnapshotReport',
    'Get-EC2VolumeReport',
    'Start-EC2RetryLoop',
    'Find-OpenSecurityGroup'
)