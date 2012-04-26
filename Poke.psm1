###########################################
#
#             POKE Toolkit 0.3
#             By Oisin Grehan (MVP)
#
###########################################

Set-StrictMode -Version Latest

# libraries to include
. (join-path $PSScriptRoot delegate.ps1)

# global cache for -ascustomobject instance/type proxies
# this is needed for the format helper functions as metadata
# and hints about proxied objects are hidden in ETS member 
# attributes
$SCRIPT:proxyTable = @{}

############################################
#
# PS1XML Format function helper definitions
#
############################################

# used in this module (poke) for property/field filter
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

function Get-Modifier {
    param(
        [parameter(mandatory=$true)]
        [validatenotnull()]
        $Member
    )

    $modifiers = ""

    try {
        if ($Member.ispublic) {
            $modifiers = "public"
        } elseif ($Member.isFamily) {
            $modifiers = "protected"
        } elseif ($Member.isFamilyOrAssembly) {
            $modifiers = "protected internal"
        } elseif ($Member.isAssembly) {
            $modifiers = "internal"
        } elseif ($Member.isPrivate) {
            $modifiers = "private"
        }
    } catch {
        $modifiers = "ERROR"
    }

    $modifiers
}

$SCRIPT:formatHelperFunctions = {
    # These functions are defined within module scope for a single instance or type proxy.

    $SCRIPT:adapterType = [psobject].assembly.gettype("System.Management.Automation.DotNetAdapter")
    $SCRIPT:getMethodDefinition = $adapterType.getmethod("GetMethodInfoOverloadDefinition", [reflection.bindingflags]"static,nonpublic")
    
    # cache some often used members for performance reasons
    $SCRIPT:miType = [psobject].assembly.gettype("System.Management.Automation.MethodInformation")
    $SCRIPT:miCtor = $mitype.GetConstructor("nonpublic,instance", $null, [type[]]@([reflection.methodinfo], [int]), $null)
    $SCRIPT:miDefinition = $mitype.GetProperty("methodDefinition", [reflection.bindingflags]"instance,nonpublic")

    # used in dynamic modules (proxies) for method filter
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

    # enhanced .ctor definition with parameter names
    function Get-ConstructorDefinition {
        param(
            [parameter(mandatory=$true)]
            [type]$Type
        )
        $type.GetConstructors("public,nonpublic,instance") | % {
            ".ctor ({0})" -f (($_.getparameters() | % {
                "{0} {1}" -f [microsoft.powershell.tostringcodemethods]::type($_.parametertype)<#.split(",")[0]#>, $_.name
            }) -join ", ")
        }
    }

    function Get-MethodDefinition {
        param(
            [parameter(mandatory=$true)]
            [validatenotnull()]
            [reflection.methodinfo]$MethodInfo
        )
        # let powershell do the work
        $mi = $miCtor.Invoke(@($MethodInfo, 0))
        $miDefinition.getvalue($mi)
    }

    function Get-MemberDefinition {
        param(
            [parameter(mandatory=$true)]
            [Microsoft.PowerShell.Commands.MemberDefinition]$Member,

            [parameter()]
            [pstypename("Pokeable.Object")]
            [psobject]$Proxy
        )

        # NOTE: we don't want to recursively trigger ETS so use psbase
        $memberType = $member.psbase.MemberType

        switch ($memberType) {
            
            ScriptProperty {
                # Property* or Field*
                $baseMemberType = $member.MemberType.split(":")[0] # grab _our_ ETS value (not using psbase!)
                $getset = $(if ($baseMemberType -eq "Property*") { " { get; set; }" })

                "{0}{1} {2}{3}" -f "", $proxy.psobject.Members[$member.Name].TypeNameOfValue, $Member.Name, $getset
            }

            ScriptMethod {
                switch ($member.Name) {
                    __CreateInstance {
                        $baseObject = $Proxy.__GetBaseObject()
                        if ($baseObject -is [type]) {
                            (Get-ConstructorDefinition -Type $baseObject) -join ", "
                        } else {
                            (Get-ConstructorDefinition -Type $baseObject.gettype()) -join ", "
                        }                        
                    }
                
                    __GetBaseObject {
                        $baseObject = $Proxy.__GetBaseObject()
                        if ($baseObject -is [type]) {
                            "type __GetBaseObject()"
                        } else {
                            "{0} __GetBaseObject()" -f [Microsoft.PowerShell.ToStringCodeMethods]::Type($baseObject.gettype())
                        }
                    }
                
                    __GetModuleInfo {
                        "psmoduleinfo __GetModuleInfo()"
                    }
                    
                    ToString {
                        "string ToString()"
                    }

                    default {
                        # retrieve from scriptmethod scriptblock attributes
                        $body = $proxy.psobject.members[$member.Name].script
                        $description = $body.Attributes.Find( { $args[0] -is [System.ComponentModel.DescriptionAttribute] })
                        if ($description) {
                            # overloads cached in description attribute above param block
                            $description.description
                        } else {
                            "..."
                        }
                    }
                }
            }
            
            Method {
                # pass through
                $Member.psbase.Definition
            }
            
            Property {
                # pass through
                $Member.psbase.definition
            }
        }

        #$definition = @()

        #foreach ($m in $MethodBase) {
        #    $definition += $getMethodDefinition.Invoke($adapterType, @($name, $m, 0))
        #}
        
        #$definition -join ", "
    }

    # computes modifiers for a memberdefinition instance (public, private, internal, static etc)
    function Get-MemberModifier {
        param(
            [parameter(mandatory=$true)]
            [Microsoft.PowerShell.Commands.MemberDefinition]$Member,

            [parameter()]
            [pstypename("Pokeable.Object")]
            [psobject]$Proxy
        )
        # modifiers are cached in exported function description
        Write-Verbose "getting function description for $($Member.psbase.name)"
        
        switch ($member.psbase.MemberType) {
            ScriptProperty {
                $getter = $proxy.psobject.members[$member.Name].getterscript
                $description = $getter.Attributes.Find( { $args[0] -is [System.ComponentModel.DescriptionAttribute] })
                $description.description.split(":")[1]
            }

            ScriptMethod {
                try {
                    $description = (get-item function:"$($Member.psbase.name)").Description
                    if ($description) {
                        $description.split(":")[0]
                    } else {
                        # special cases
                        if ($member.psbase.name -eq "ToString") {
                            "public"
                        } else {
                            # special case proxy helpers, like __CreateInstance, __GetModuleInfo etc
                            "-"
                        }
                    }
                } catch { "-" } # no description property on function
            }
            default { "public" }
        }
    }

    # computes member type for a memberdefinition (e.g. replaces ScriptProperty with Field or Property
    # and ScriptMethod with Method)
    function Get-MemberType {
        param(
            [parameter(mandatory=$true)]
            [Microsoft.PowerShell.Commands.MemberDefinition]$Member,
            
            [parameter()]
            [pstypename("Pokeable.Object")]
            [psobject]$Proxy
        )

        # don't want to recursive trigger ETS so use psbase
        $memberType = $member.psbase.MemberType

        switch ($memberType) {
            ScriptProperty {
                # the proxied member type is cached in a description attribute on the scriptproperty's getterscript (e.g. field/property)
                $getter = $proxy.psobject.members[$member.Name].getterscript
                $description = $getter.Attributes.Find( { $args[0] -is [System.ComponentModel.DescriptionAttribute] })
                $description.description.split(":")[0]
            }
            ScriptMethod {
                # add asterisk to differentiate between methods on the psobject (gettype etc) and proxied members
                "Method*"
            }
            default {
                # catch all
                $memberType
            }
        }
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

    Write-Progress -Id 1 -Activity "Peek" -Status "Initializing methods..."

    write-verbose "Method initializer."

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
        #$returnType = [Microsoft.PowerShell.ToStringCodeMethods]::type($method.returnType).split(",")[0] # trim fully qualified types

        write-verbose "Creating method $methodname`(...`); building method definitions..."
        $overloads = ($methodInfos|? name -eq $methodName|% { Get-MethodDefinition $_ }) -join ", "

        # psscriptmethod ignores outputtype - maybe this will get fixed in later releases of ps?
        # ultimately it's of dubious use for methods as overloads may differ in return type
        # of course they must have differing parameters too as a method cannot differ _only_ by return type.
        $definition = new-item function:$methodName -value ([scriptblock]::create("
            # cache overloads in description attribute which is easily retrieved from this
            # scriptblock's attributes property when emitting memberdefinition definition
            [componentmodel.description('$overloads')]
            param();
                
            write-verbose 'called $methodName'
            [reflection.bindingflags]`$binding = '$flags'

            try {
                if ((`$overloads = @(`$baseType.getmethods(`$binding)|? name -eq '$methodname')).count -gt 1) {
                    write-verbose 'self $self ; flags: $flags ; finding best fit overload'
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

                # TODO: remove this redundant check

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

        $modifiers = ""
        if ($method.ispublic) {
            $modifiers = "public"
        } elseif ($method.isFamily) {
            $modifiers = "protected"
        } elseif ($method.isFamilyOrAssembly) {
            $modifiers = "protected internal"
        } elseif ($method.isAssembly) {
            $modifiers = "internal"
        } elseif ($method.isPrivate) {
            $modifiers = "private"
        }
        
        $definition.description = $modifiers + ":" + $(if ($method.isstatic) { "static" } else { "" })
        
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
                Get-ConstructorDefinition $type | % { write-host -ForegroundColor green " $_" }
                return 
            }

            # return wrapped object
            try {
                New-InstanceProxy $ctor.invoke($args) -verbose
            } catch {
                write-warning "Could not create instance: $_"
            }
        }
        
        $self = $type

        # bind format helper functions to this module's scope
        . apply $formatHelperFunctions        

        # define methods
        . apply $initializer $type "Public,NonPublic,Static,DeclaredOnly"
         
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
    
        $proxy.psobject.typenames.insert(0, "Pokeable.Object")
        $proxy.psobject.typenames.insert(0, "Pokeable.System.RuntimeType#$($type.fullname)")

        Add-fields $proxy "Public,NonPublic,DeclaredOnly,Static" > $null
        Add-properties $proxy "Public,NonPublic,DeclaredOnly,Static" > $null

        write-verbose "Registering in proxyTable"
        $proxyTable[$proxy.tostring()] = $proxy

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

        # bind format helper functions to this module's scope
        . apply $formatHelperFunctions
        
        # define methods
        . apply $initializer $self "Public,NonPublic,DeclaredOnly,Instance"

        function __GetModuleInfo {
            $ExecutionContext.SessionState.Module
        }

        function __GetBaseObject {
            $self
        }
        
        function ToString() {
            "Pokeable.$($type.fullname)#$instanceId"
        }

        export-modulemember __GetBaseObject, __GetModuleInfo, ToString

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
        
        $psobject.typenames.insert(0, "Pokeable.Object")
        $psobject.typenames.insert(0, "Pokeable.$($type.fullname)#$instanceId")

        Add-fields $proxy "Public,NonPublic,DeclaredOnly,Instance" > $null        
        Add-properties $proxy "Public,NonPublic,DeclaredOnly,Instance" > $null

        write-verbose "Registering in proxyTable"
        $proxyTable[$proxy.tostring()] = $proxy
                
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
        [pstypename("Pokeable.Object")]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    Write-Progress -Id 1 -Activity "Peek" -Status "Initializing fields..."

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
    foreach ($field in ($fields|limit-specialmember|sort name)) {
        
        # clean up type string for generics and accelerated types
        $outputType = [Microsoft.PowerShell.ToStringCodeMethods]::type($field.FieldType)<#.split(",")[0]#> # trim fully qualified types

        $modifiers = Get-Modifier $field

        # close over field and instance vars but insert literal for fieldtype
        $getter = [scriptblock]::create(
            "[componentmodel.description('Field*:$modifiers')][outputtype('$outputtype')]param(); `$field.GetValue(`$self)").GetNewClosure()
        
        # stash some metadata on the getter
        #$getter.Attributes.Add((new-object System.ComponentModel.DescriptionAttribute "Field*"))

        # declared readonly?
        if ($field.IsInitOnly) {
            $fieldDef = New-Object management.automation.psscriptproperty $field.Name, $getter
        } else {
            # TODO: strongly type $value parameter in setter
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
        [pstypename("Pokeable.Object")]
        $baseObject,

        [Parameter(mandatory=$true, position=1)]
        [reflection.bindingflags]$flags
    )

    Write-Progress -Id 1 -Activity "Peek" -Status "Initializing properties..."

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
    foreach ($property in ($properties|limit-specialmember|sort name)) {

        # clean up type string for generics and accelerated types
        $outputType = [Microsoft.PowerShell.ToStringCodeMethods]::type($property.PropertyType)<#.split(",")[0]#> # trim fully qualified output

        $getmethod = $property.GetMethod
        $setmethod = $(if ($property.CanWrite) { $property.SetMethod } else { $getmethod })

        if ((Get-Modifier $getmethod) -eq (Get-Modifier $setmethod)) {
            # readonly prop, or getter/setter have same visibility
            $modifiers = Get-Modifier $getmethod
        } else {
            # getter/setter have different visibility
            # TODO: highlight this in definition with { private get; internal set; }
            $modifiers = "-"
        }

        # property getter
        $getter = [scriptblock]::create(
            "[componentmodel.description('Property*:$modifiers')][outputtype('$outputType')]param(); `$property.GetValue(`$self)").GetNewClosure()

        # stash some metadata on the getter scriptblock
        #$getter.Attributes.Add((new-object System.ComponentModel.DescriptionAttribute "Property*"))
        
        # i don't account for setter-only properties
        if (-not $property.CanWrite) {
            $propertyDef = New-Object management.automation.psscriptproperty $property.Name, $getter
        } else {
            # TODO: strongly type $value parameter in setter
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

    Write-Progress -id 1 -Activity "Poke" -Completed
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
            # invoke the command in the scope of the module that proxies this type or instance
            & $proxyTable[$Member.TypeName].__GetModuleInfo() $CommandName $Member $proxy @args
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

# scriptblock is not bound to this module's scope? weird bug? we have to use invoke-format helper to lookup module in a shared global
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