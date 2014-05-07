﻿Clear-Host

Set-Location $psscriptroot
Import-Module .\poke.psd1 -force

#$VerbosePreference = "Continue"
$error.Clear()

function Assert-True {
    param(
        [parameter(position=0, mandatory=$true)]
        [validatenotnull()]
        [scriptblock]$Script,

        [parameter(position=1)]
        [validatenotnullorempty()]
        [string]$Name = 'Assert-True'
    )    
    $eap = $ErrorActionPreference
    
    $detail = "Assert-True [ $Name ] "
    Write-Host -NoNewline $detail

    try {
        $erroractionpreference = 'stop'
        if ((& $script) -eq $true) {
            write-host -ForegroundColor Green "$(' ' * (100 - $detail.Length))[PASS]"
            return
        }
        $reason = 'Assert failed.'
    }
    catch {
        $reason = "Error: $_"
    }
    finally {
        $ErrorActionPreference = $eap
    }
    write-host -ForegroundColor Red "$(' ' * (100 - $detail.Length))[FAIL] " -NoNewline
    write-host "Reason: '$reason'"
}

#
# begin tests
#

assert-true {
    $proxy = peek -name System.Text.StringBuilder
    ($proxy | Get-Member | Measure-Object).count -eq 15
} -name 'type proxy'

assert-true {
    $sb = new-object System.Text.StringBuilder
    $proxy = peek $sb
    ($proxy | Get-Member | Measure-Object).count -eq 38
} -name 'instance proxy'

assert-true {
    $sb = new-object System.Text.StringBuilder
    $proxy = peek $sb
    $proxy.length -eq 0
} -name 'instance property'

assert-true {
    $sb = new-object System.Text.StringBuilder
    $proxy = peek $sb
    $proxy.append(42) > $null
    $proxy.length -eq 2
} -name 'instance method with overloads'

assert-true {
    $proxy = peek -name system.string
    $s = $proxy.format('hello, {0}', [object[]]@('world'))
    $s -eq 'hello, world'
} -name 'static method with overloads'


#
# static methods
#

assert-true {
    $delegate = [string]::format | Get-Delegate -Delegate 'func[string,object,string]'
    $delegate.invoke('hello, {0}', 'world') -eq 'hello, world'
} -name "[string]::format | get-delegate -delegate 'func[string,object,string]'"

assert-true {
    $delegate = [console]::writeline | Get-Delegate -Delegate 'action[int]'
    $delegate -is [action[int]]
} -name "[console]::writeline | get-delegate -delegate 'action[int]'"

assert-true {
    $delegate = [string]::format | Get-Delegate string,string
    $delegate.invoke('hello, {0}', 'world') -eq 'hello, world'
} -name '[string]::format | get-delegate string,string'

assert-true {
    $delegate = [console]::beep | Get-Delegate @()
    $delegate -is [action]
} -name '[console]::beep | get-delegate @()'

assert-true {
    $delegate = [console]::beep | Get-Delegate -DelegateType action
    $delegate -is [action]
} -name '[console]::beep | Get-Delegate -DelegateType action'

assert-true {
    $delegate = [string]::IsNullOrEmpty | get-delegate
    $delegate -is [func[string,bool]]
} -name '[string]::IsNullOrEmpty | get-delegate # single overload'

assert-true {
    $delegate = [string]::IsNullOrEmpty | get-delegate string
    $delegate -is [func[string,bool]]
} -name '[string]::IsNullOrEmpty | get-delegate string # single overload'

#
# instance methods
#

assert-true {
    $sb = new-object text.stringbuilder
    $delegate = $sb.Append | get-delegate string
    $delegate -is [System.Func[string,System.Text.StringBuilder]]
} -name "`$sb.Append | get-delegate string"

assert-true {
    $sb = new-object text.stringbuilder
    $delegate = $sb.AppendFormat | get-delegate string, int, int
    $delegate -is [System.Func[string,object,object,System.Text.StringBuilder]]
} -name "`$sb.AppendFormat | get-delegate string, int, int"


#
# readonly field
#

assert-true {
  $re = peek ([regex])
  $re.DefaultMatchTimeout = New-TimeSpan -Seconds 42
  $re.DefaultMatchTimeout.Seconds -eq 42
} -name 'readonly static field (setter)'

$VerbosePreference = 'SilentlyContinue'

$s = peek system.string
$s | Get-Member | Sort-Object modifier | Format-Table -group modifier
