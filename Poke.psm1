###########################################
#
#             POKE Toolkit 0.2
#             By Oisin Grehan (MVP)
#
###########################################

Set-StrictMode -Version Latest

$SCRIPT:proxyTable = @{}

############################################
#
# PS1XML Format function helper definitions
#
############################################

$SCRIPT:formatHelperFunctions = {
    # These functions are defined within module scope for a single instance or type proxy.

    $SCRIPT:adapterType = [psobject].assembly.gettype("System.Management.Automation.DotNetAdapter")
    $SCRIPT:getMethodDefinition = $adapterType.getmethod("GetMethodInfoOverloadDefinition", [reflection.bindingflags]"static,nonpublic")
    
    function Get-MemberDefinition {
        param(
            [parameter(mandatory=$true)]
            [validatenotnullorempty()]
            [string]$Name #,

<#
            [parameter(mandatory=$true, valuefrompipeline=$true)]
            [validatenotnull()]
            [reflection.methodbase[]]$MethodBase
#>
        )

        begin {
            $definition = @()
        }

        process {
            #foreach ($m in $MethodBase) {
            #    $definition += $getMethodDefinition.Invoke($adapterType, @($name, $m, 0))
            #}
        }

        end {
            $definition -join ", "
        }
    }

    function Get-MemberModifier {
        param(
            [parameter(mandatory=$true)]
            [Microsoft.PowerShell.Commands.MemberDefinition]$PSMethod
        )
        # modifiers are cached in exported function description
        Write-Verbose "getting function description for $($psmethod.psbase.name)"
        
        $description = (get-item function:"$($psmethod.psbase.name)").Description
        if ($description) {
            $description.split(":")[0]
        }        
    }

    function Get-MemberType {
        param(
            [Microsoft.PowerShell.Commands.MemberDefinition]$Member
        )

        # don't want to recursive trigger ETS so use psbase
        $memberType = $member.psbase.MemberType
        $memberType
    }
}

############################################
#
# Proxy Method generator definition (lambda)
#
############################################

$SCRIPT:initializer = {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags,

        [switch]$IncludeCompilerGenerated,

        [switch]$IncludeSpecialName
    )

    write-verbose "Method initializer."

    filter Limit-SpecialMember {
        if (-not ($_.isspecialname -or $_.GetCustomAttributes([System.Runtime.CompilerServices.CompilerGeneratedAttribute], $false).count)) {
            $_
        } else {
            if ($_.isspecialname) {
                Write-Verbose "skipping special member $_"
            } else {
                Write-Verbose "skipping compiler generated $_"
            }
        }
    }

    if ($baseObject.gettype().Name -eq "RuntimeType") {
        # type
        Write-Verbose "`$baseObject is a Type"
        $methodInfos = $baseobject.getmethods($flags)| Limit-SpecialMember
        $baseType = $baseObject
    } else {
        # instance
        Write-Verbose "`$baseObject is an instance"
        $methodInfos = $baseObject.GetType().getmethods($flags) | Limit-SpecialMember
        $baseType = $baseObject.GetType()
    }

    foreach ($method in @($methodInfos|sort name -unique)) {

        $methodName = $method.name
        $returnType = [Microsoft.PowerShell.ToStringCodeMethods]::type($method.returnType)

        write-verbose "Creating method $returntype $methodname`(...`)"
            
        # psscriptmethod ignores outputtype - maybe this will get fixed in later releases of ps?
        $definition = new-item function:$methodName -value ([scriptblock]::create("
            [outputtype('$returntype')]
            param();
                
            write-verbose 'called $methodName'
            [reflection.bindingflags]`$binding = '$flags'

            try {
                if ((`$overloads = @(`$baseType.getmethods(`$binding)|? name -eq '$methodname')).count -gt 1) {
                    write-verbose 'self $self ; flags: $flags ; finding best fit overload'
                    #write-warning ""multiple overloads (`$(`$overloads.count))""
                    `$types = [type]::gettypearray(`$args)
                    `$method = `$baseType.getmethod('$methodname', `$binding, `$null, `$types, `$null)
                    if (-not `$method) {
                        write-warning ""Could not find best fit overload for `$(`$types -join ',').""
                        throw
                    }
                } else {
                    write-verbose 'single method; no overloads'
                }
                # invoke
                `$method.invoke(`$self, `$binding, `$null, `$args, `$null)                                    
            } catch {
                if (`$_.exception.innerexception -is [Reflection.TargetParameterCountException]) {
                        
                    write-warning ""Could not find matching overload with `$(`$args.count) parameter(s).""
                    # dump overloads (public methods only?)
                    #`$self.'$methodname'

                } else {
                    # error is from invocation target, rethrow
                    throw
                }
            }")).GetNewClosure()
            
        # isfamily: protected
        # isfamilyORassembly: protected internal
        # isassembly: internal
        # isprivate: private
        
        # methodattributes are a bit obtuse
        #$definition.description = $method.attributes.tostring() + ":(overloads)"

        $modifiers = @()
        if ($method.ispublic) {
            $modifiers += "public"
        } elseif ($method.isFamily) {
            $modifiers += "protected"
        } elseif ($method.isFamilyOrAssembly) {
            $modifiers += "protected internal"
        } elseif ($method.isAssembly) {
            $modifiers += "internal"
        } elseif ($method.isPrivate) {
            $modifiers += "private"
        }
        
        if ($method.isstatic) {
            $modifiers += "static"
        }
        
        $definition.description = ($modifiers -join ", ") + ":(overloads)"

        
        export-modulemember $methodname
    } # /foreach method
}

############################################
#
# Type Proxy
#
############################################

function New-TypeProxy {
<#

#>
    [cmdletbinding()]
    param(        
        [parameter()]
        [validatenotnullorempty()]
        [string]$TypeName,
        [switch]$CaseSensitive
    )

    $type = Find-Type $typeName `
        -CaseSensitive:$CaseSensitive                

    if (-not $type) {
        write-warning "Could not find ${typeName}. Are you sure the containing assembly has been loaded?"
        return
    }
        
    # Create TypeProxy
    $proxy = new-module -ascustomobject -name "Pokeable.System.RuntimeType#$($type.fullname)" {
        param(
            [type]$type,
            [scriptblock]$initializer,
            [scriptblock]$formatHelperFunctions
        )
         
        Set-StrictMode -Version latest

        function apply {
            param([scriptblock]$block)
            . $ExecutionContext.SessionState.Module.NewBoundScriptBlock($block) @args
        }

        function __CreateInstance {
            write-verbose "Type is $type ; `$args count is $($args.count)"

            if ($type.IsAbstract) {
                write-warning "Type is abstract."
                return
            }
            
            $types = @()
            $args|%{if($_ -eq $null){$types+=$null}else{$types+=$_.gettype()}}
            write-verbose ".ctor args: length $($types.length)"

            $ctor = $type.GetConstructor("Public,NonPublic,Instance", $null, $types, $null)

            if (-not $ctor) {
                write-warning "No matching constructor found. Available constructors:"
                $type.getconstructors("Public,NonPublic,Instance") | % { write-host -ForegroundColor Green " $_" }
                return 
            }

            # return wrapped object
            try {
                New-InstanceProxy $ctor.invoke($args) -verbose
            } catch {
                write-warning "Could not create instance: $_"
            }
        }

        # define methods
        $self = $type
        . apply $initializer $type "Public,NonPublic,Static,DeclaredOnly"
         
        # bind format helper functions to this module's scope
        . apply $formatHelperFunctions        

        function __GetBaseObject {
            $type
        }
        
        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }
        
        function ToString {
            "Pokeable.System.RuntimeType#$($type.fullname)"
        }        

        export-modulemember __CreateInstance, __GetBaseObject, __GetModuleInfo, ToString
        
    } -args $type, $initializer, $formatHelperFunctions
    
    if ($proxy) {
        
        # TODO: fix up overloads
    
        $proxy.psobject.typenames.insert(0, "Pokeable.Object")
        $proxy.psobject.typenames.insert(0, "Pokeable.System.RuntimeType#$($type.fullname)")

        # TODO: create field/property initializer lambdas
        Add-fields $proxy "Public,NonPublic,DeclaredOnly,Static" > $null        
        Add-properties $proxy "Public,NonPublic,DeclaredOnly,Static" > $null

        write-verbose "Registering in proxyTable"
        $proxyTable[$proxy.tostring()] = $proxy.__GetModuleInfo()

        $proxy
    }
}    

############################################
#
#  Instance Proxy
#
############################################

function New-InstanceProxy {
<#

#>
    [cmdletbinding()]
    param(
        [parameter(mandatory=$true)]
        [validatenotnull()]
        [object]$Instance,
        [switch]$IncludeInheritedMembers, # not implemented
        [switch]$ExcludePublic, # not implemented
        [switch]$ExcludeFields # not implemented
    )
    
    $instanceId = [guid]::NewGuid()
        
    $type = $instance.GetType()
    
    #$methods = $type.GetMethods("Public,NonPublic,DeclaredOnly,Instance")|?{!$_.isspecialname}
        
    $proxy = new-module -ascustomobject -name "Pokeable.$($type.fullname)#$instanceId" -verbose {
        param(
            $self,
            $instanceId,
            [scriptblock]$initializer,
            [scriptblock]$formatHelperFunctions
        )
        
        Set-StrictMode -Version latest
    
        function apply {
            param([scriptblock]$block)
            . $ExecutionContext.SessionState.Module.NewBoundScriptBlock($block) @args
        }

        $type = $self.gettype()
        write-verbose "Created an instance of $type"

        # define methods
        . apply $initializer $self "Public,NonPublic,DeclaredOnly,Instance"

        # bind format helper functions to this module's scope
        . apply $formatHelperFunctions

        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }

        function __GetBaseObject {
            $self
        }      
        
        function __Help {
            param([string]$MethodName)
            throw "Not implemented."
        }
        
        function ToString() {
            "Pokeable.$($type.fullname)#$instanceId"
        }

        export-modulemember __GetBaseObject, __GetModuleInfo, ToString #, __Help

        # register dispose handler on module remove
        $ExecutionContext.SessionState.Module.OnRemove = {

            # TODO: handle Close
            if ($self.Dispose) { # -as IDisposable?

                # will fail on explicit idisposable.dispose
                $self.Dispose()
            }
        }
    } -args $instance, $instanceId, $initializer, $formatHelperFunctions
    
    if ($proxy) {
    
        $psobject = $proxy.psobject
        
        try {
            <# fix up overload definitions ;-)
            foreach ($method in ($methods|group name|sort name)) {
                $overloads = $psobject.methods[$method.name].overloaddefinitions
                write-verbose $($method.name + " has " + $method.group.count + " overload(s)")
                $overloads.clear()
                $method.group | % { $overloads.add($_) }
            }
            #>
        } catch {
            write-warning "Failed to fix up overloads: $_"        
        }
        
        Add-fields $proxy "Public,NonPublic,DeclaredOnly,Instance" > $null
        
        Add-properties $proxy "Public,NonPublic,DeclaredOnly,Instance" > $null

        $psobject.typenames.insert(0, "Pokeable.Object")
        $psobject.typenames.insert(0, "Pokeable.$($type.fullname)#$instanceId")

        write-verbose "Registering in proxyTable"
        $proxyTable[$proxy.tostring()] = $proxy.__GetModuleInfo()
                
        $proxy
    }
}

############################################
#
#  Add Fields
#
############################################

function Add-Fields {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    if ($baseObject.__GetBaseObject() -is [type]) {
        $type = $baseObject.__GetBaseObject()
        $self = $type
    } else {
        $type = $baseObject.__GetBaseObject().gettype()
        $self = $baseObject.__GetBaseObject()
    }

    $fields = $type.getfields($flags)
    $psobject = $baseObject.psobject

    # add fields
    foreach ($field in ($fields|sort name)) {
        
        # clean up type string for generics and accelerated types
        $outputType = [Microsoft.PowerShell.ToStringCodeMethods]::type($field.FieldType)

        # close over field and instance vars but insert literal for fieldtype
        $getter = [scriptblock]::create(
            "[outputtype('$outputtype')]param(); `$field.GetValue(`$self)").GetNewClosure()
        
        # declared readonly?
        if ($field.IsInitOnly) {
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter
        } else {
            $setter = { param($value); $field.SetValue($self, $value) }.GetNewClosure()
            
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter, $setter
        }
        write-verbose "Adding $flags field $($field.name)"
        $psobject.properties.add($fieldDef)
    }
}

############################################
#
#  Add Properties
#
############################################

function Add-Properties {
    param(
        [Parameter(mandatory=$true, position=0)]
        [validatenotnull()]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    if ($baseObject.__GetBaseObject() -is [type]) {
        $type = $baseObject.__GetBaseObject()
        $self = $type
    } else {
        $type = $baseObject.__GetBaseObject().gettype()
        $self = $baseObject.__GetBaseObject()
    }
    $properties = $type.getproperties($flags)
    $psobject = $baseObject.psobject
    

    # add properties
    foreach ($property in ($properties|sort name)) {

        # clean up type string for generics and accelerated types
        $outputType = [Microsoft.PowerShell.ToStringCodeMethods]::type($property.PropertyType)

        # property getter
        $getter = [scriptblock]::create(
            "[outputtype('$outputType')]param(); `$property.GetValue(`$self)").GetNewClosure()
        
        # i don't account for setter-only properties
        if (-not $property.CanWrite) {
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter
        } else {
            # property setter
            $setter = { param($value); $property.SetValue($self, $value) }.GetNewClosure()            
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter, $setter
        }
        write-verbose "Adding $flags property $($property.name)"
        $psObject.properties.add($propertyDef)
    }
}

############################################
#
#  Find Type
#
############################################

function Find-Type {
    param(
        [string]$TypeName,
        [reflection.bindingflags]$BindingFlags = "Public,NonPublic",
        [switch]$CaseSensitive
    )
    
    write-verbose "Searching for $typeName"

    $assemblies = [appdomain]::CurrentDomain.GetAssemblies()
        
    $matches = @()
    
    $assemblies | % {
        write-verbose "Searching $($_.getname().name)..."
        
        $match = $_.gettype($typename, $false, !$CaseSensitive)
        if ($match) {
            $matches += $match
        }        
    }
    
    write-verbose "Found $($matches.length) match(es)."
        
    $matches
}

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
                    $DelegateType = ("action[{0}]" -f ($ParameterType -join ",")) -as [type]
                }
            } else {
                # func<...>

                # replace desired with matching overload parameter types
                #$ParameterType = $methodInfo.GetParameters().ParameterType
                $DelegateType = ("func[{0}]" -f (($ParameterType + $methodInfo.ReturnType) -join ",")) -as [type]
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

############################################
#
#  New Object Proxy (peek)
#
############################################

function New-ObjectProxy {
    [cmdletbinding(defaultparametersetname="typeName")]
    param(                
        [parameter(position=0, mandatory=$true, parametersetname="typeName")]
        [validatenotnullorempty()]
        [string]$TypeName,
        
        [parameter(position=0, mandatory=$true, parametersetname="type")]
        [validatenotnull()]
        [type]$Type,

        [parameter(parametersetname="typeName")]
        [switch]$CaseSensitive,
        
        [parameter(position=0, mandatory=$true, parametersetname="instance")]
        [validatenotnull()]
        [object]$Instance
    )
    
    if ($PSCmdlet.ParameterSetName -eq "instance") {
    
        New-InstanceProxy -instance $instance
    
    } else {
        
        if ($PSCmdlet.ParameterSetName -eq "type") {
            $typeName = $type.fullname
        }
        
        New-TypeProxy -TypeName $TypeName -CaseSensitive:$CaseSensitive
    }
}

function ConvertTo-CliXml {
    param(
        [parameter(position=0,mandatory=$true,valuefrompipeline=$true)]
        [validatenotnull()]
        [psobject]$object
    )
    begin {
        $type = [psobject].assembly.gettype("System.Management.Automation.Serializer")
        $ctor = $type.getconstructor("instance,nonpublic", $null, @([xml.xmlwriter]), $null)
        $sw = new-object io.stringwriter
        $xw = new-object xml.xmltextwriter $sw
        $serializer = $ctor.invoke($xw)
        $method = $type.getmethod("Serialize", "nonpublic,instance", $null, [type[]]@([object]), $null)
        $done = $type.getmethod("Done", [reflection.bindingflags]"nonpublic,instance")
    }
    process {
        try {
            $method.invoke($serializer, $object)
        } catch {
            write-warning "Could not serialize $($object.gettype()): $_"
        }
    }
    end {    
        $done.invoke($serializer, @())
        $sw.ToString()
    }
}

<#
Update-TypeData -Force -TypeName System.Management.Automation.PSMethod -MemberType ScriptMethod -MemberName CreateDelegate -Value {
    param(        
        [parameter(position=0, mandatory=$true)]
        [validatenotnull()]
        [validatescript({ ([delegate].isassignablefrom($_)) })]
        [type]$DelegateType
    )

    $this | Get-Delegate -Delegate $DelegateType
}
#>

function Invoke-FormatHelper {
    param(
        [parameter()]
        [Microsoft.PowerShell.Commands.MemberDefinition]$Member,
        [parameter()]
        [string]$CommandName,
        [parameter()]
        [string]$DefaultValue
    )
    $proxy = $proxyTable[$Member.TypeName]
    if ($proxy) {
        try {
            & $proxyTable[$Member.TypeName] $CommandName $Member @args
        } catch {
            write-warning $_
            $DefaultValue
        }
    } else {
        # not a proxied type or instance
        $DefaultValue
    }
}

#update-formatdata -PrependPath (join-path $ExecutionContext.SessionState.Module.ModuleBase 'Poke.Format.ps1xml')

# scriptblock is not bound to this module's scope? weird bug?
Update-TypeData -typename Microsoft.PowerShell.Commands.MemberDefinition -MemberType ScriptProperty -MemberName MemberType -Value {    
    try { invoke-formathelper $this get-membertype -default $this.psbase.membertype } catch { write-warning "get-membertype: $_" }
} -Force

Update-TypeData -typename Microsoft.PowerShell.Commands.MemberDefinition -MemberType ScriptProperty -MemberName Modifier -Value {    
    try { invoke-formathelper $this get-membermodifier -default "public" } catch { write-warning "get-membermodifier: $_" }
} -Force

# overloads
Update-TypeData -typename Microsoft.PowerShell.Commands.MemberDefinition -MemberType ScriptProperty -MemberName Definition -Value {    
    try { invoke-formathelper $this get-memberdefinition -default $this.psbase.definition } catch { write-warning "get-memberdefinition: $_" }
} -Force

new-alias -Name peek -Value New-ObjectProxy -Force
Export-ModuleMember -Alias peek -Function New-ObjectProxy, New-TypeProxy, New-InstanceProxy, Get-Delegate, Invoke-FormatHelper