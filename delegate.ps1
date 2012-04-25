############################################
#
#  Get Delegate
#
############################################

function Get-Delegate {
<#
.SYNOPSIS
Create an action[] or func[] delegate for a psmethod reference.
.DESCRIPTION
Create an action[] or func[] delegate for a psmethod reference.
.PARAMETER Method
A PSMethod reference to create a delegate for. This parameter accepts pipeline input.
.PARAMETER ParameterType
An array of types to use for method overload resolution. If there are no overloaded methods
then this array will be ignored but a warning will be omitted if the desired parameters were
not compatible.
.PARAMETER DelegateType
The delegate to create for the corresponding method. Example: [string]::format | get-delegate -delegatetype func[int,string]
.INPUTS System.Management.Automation.PSMethod, System.Type[]
.EXAMPLE
$delegate = [string]::format | Get-Delegate string,string

Gets a delegate for a matching overload with string,string parameters.
It will actually return func<object,string> which is the correct 
signature for invoking string.format with string,string.
.EXAMPLE
$delegate = [console]::beep | Get-Delegate @()

Gets a delegate for a matching overload with no parameters.
.EXAMPLE
$delegate = [console]::beep | get-delegate int,int

Gets a delegate for a matching overload with @(int,int) parameters.
.EXAMPLE
$delegate = [string]::format | Get-Delegate -Delegate 'func[string,object,string]'

Gets a delegate for an explicit func[].
.EXAMPLE
$delegate = [console]::writeline | Get-Delegate -Delegate 'action[int]'

Gets a delegate for an explicit action[].
.EXAMPLE
$delegate = [string]::isnullorempty | get-delegate 

For a method with no overloads, we will choose the default method and create a corresponding action/action[] or func[].
#>
    [CmdletBinding(DefaultParameterSetName="FromParameterType")]
    [outputtype('System.Action','System.Action[]','System.Func[]')]
    param(
        [parameter(mandatory=$true, valuefrompipeline=$true)]
        [system.management.automation.psmethod]$Method,

        [parameter(position=0, valuefromremainingarguments=$true, parametersetname="FromParameterType")]
        [validatenotnull()]
        [allowemptycollection()]
        [Alias("types")]
        [type[]]$ParameterType = @(),

        [parameter(mandatory=$true, parametersetname="FromDelegate")]
        [validatenotnull()]
        [validatescript({ ([delegate].isassignablefrom($_)) })]
        [type]$DelegateType
    )

    $base = $method.GetType().GetField("baseObject","nonpublic,instance").GetValue($method)    
    
    if ($base -is [type]) {
        [type]$baseType = $base
        [reflection.bindingflags]$flags = "Public,Static"
    } else {
        [type]$baseType = $base.GetType()
        [reflection.bindingflags]$flags = "Public,Instance"
    }

    if ($pscmdlet.ParameterSetName -eq "FromDelegate") {
        write-verbose "Inferring from delegate."

        if ($DelegateType -eq [action]) {
            # void action        
            $ParameterType = [type[]]@()
        
        } elseif ($DelegateType.IsGenericType) {
            # get type name
            $name = $DelegateType.Name

            # is it [action[]] ?
            if ($name.StartsWith("Action``")) {
    
                $ParameterType = @($DelegateType.GetGenericArguments())    
            
            } elseif ($name.StartsWith("Func``")) {
    
                # it's a [func[]]
                $ParameterType = @($DelegateType.GetGenericArguments())
                $ParameterType = $ParameterType[0..$($ParameterType.length - 2)] # trim last element (TReturn)
            } else {
                throw "Unsupported delegate type: Use Action<> or Func<>."
            }
        }
    }

    [reflection.methodinfo]$methodInfo = $null

    if ($Method.OverloadDefinitions.Count -gt 1) {
        # find best match overload
        write-verbose "$($method.name) has multiple overloads; finding best match."

        $finder = [type].getmethod("GetMethodImpl", [reflection.bindingflags]"NonPublic,Instance")

        write-verbose "base is $($base.gettype())"

        $methodInfo = $finder.invoke(
            $baseType,
             @(
                  $method.Name,
                  $flags,
                  $null,
                  $null,
                  [type[]]$ParameterType,
                  $null
             )
        ) # end invoke
    
    } else {
        # method not overloaded
        Write-Verbose "$($method.name) is not overloaded."
        if ($base -is [type]) {
            $methodInfo = $base.getmethod($method.name, $flags)
        } else {
            $methodInfo = $base.gettype().GetMethod($method.name, $flags)
        }

        # if parametertype is $null, fill it out; if it's not $null,
        # override it to correct it if needed, and warn user.
        if ($pscmdlet.ParameterSetName -eq "FromParameterType") {           
            if ($ParameterType -and ((compare-object $parametertype $methodinfo.GetParameters().parametertype))) { #psv3
                write-warning "Method not overloaded: Ignoring provided parameter type(s)."
            }
            $ParameterType = $methodInfo.GetParameters().parametertype
            write-verbose ("Set default parameters to: {0}" -f ($ParameterType -join ","))
        }
    }

    if (-not $methodInfo) {
        write-warning "Could not find matching signature for $($method.Name) with $($parametertype.count) parameter(s)."
    } else {        
        write-verbose "MethodInfo: $methodInfo"

        # it's important here to use the actual MethodInfo's parameter types,
        # not the desired types ($parametertype) because they may not match,
        # e.g. asked for method(int) but match is method(object).

        if ($pscmdlet.ParameterSetName -eq "FromParameterType") {
            
            if ($methodInfo.GetParameters().count -gt 0) {
                $ParameterType = $methodInfo.GetParameters().ParameterType #psv3
            }
            
            # need to create corresponding [action[]] or [func[]]
            if ($methodInfo.ReturnType -eq [void]) {
                if ($ParameterType.Length -eq 0) {
                    $DelegateType = [action]
                } else {
                    # action<...>
                    
                    # replace desired with matching overload parameter types
                    #$ParameterType = $methodInfo.GetParameters().ParameterType
                    $DelegateType = ("action[{0}]" -f (($ParameterType|%{"[{0}]" -f $_}) -join ",")) -as [type]
                }
            } else {
                # func<...>

                # replace desired with matching overload parameter types
                # need to wrap each type parameter in [ and ] for cases like int[] as "func[int[], int]" is invalid
                # the correct format is "func[[int[]], [int]]" even though "func[int,int]" is fine.
                $DelegateType = ("func[{0}]" -f ((($ParameterType + $methodInfo.ReturnType)|% {"[{0}]" -f $_}) -join ",")) -as [type]
            }                        
        }
        Write-Verbose $DelegateType

        if ($flags -band [reflection.bindingflags]::Instance) {
            $methodInfo.createdelegate($DelegateType, $base)
        } else {
            $methodInfo.createdelegate($DelegateType)
        }
    }
}
