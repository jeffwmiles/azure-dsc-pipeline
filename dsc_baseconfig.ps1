Configuration dsc_baseconfig {

    Import-DscResource -ModuleName InfraBuildDSC

Node $AllNodes.NodeName
    {
        # Everyone gets the baseline
        baseline baselineconfig {
        }

        if ($Node.Role -eq "Database"){
            db databaseconfig {
                DependsOn = "[baseline]baselineconfig"
            }
        }

        if ($Node.Role -eq "WebServer"){
            web webconfig {
                DependsOn = "[baseline]baselineconfig"
            }
        }

    } # End All Nodes
} # End Configuration