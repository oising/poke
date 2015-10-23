Describe 'Poke' {
    Import-Module -Force $PSScriptRoot\poke.psd1    
    
    Context 'regression tests' {
        # https://github.com/oising/poke/issues/4 
        It 'can poke a class with a method conflicting with a function' {
            function MMM() {}

            Add-Type @'
namespace NNN
{
    public class CCC
    {
        private static void MMM() {}
    }
}
'@
            [NNN.CCC] | peek | Should Not Be $null
        }
    }
}
