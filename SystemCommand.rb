
class SystemCommand

    class Failure < Exception
    end
    
    def initialize
        @dry_run = false
        @fail_soft = false
        @verbose = true
    end

    def setDryRun(dry_run)
        @dry_run = dry_run
    end

    def failSoft(fail_soft)
        @fail_soft = fail_soft
    end

    def setVerbose(verbose = true)
        @verbose = verbose
    end

    def handleExitCode(ec_)
        if (!ec_.exited?)
            raise Failure.new
        end
        ec = ec_.exitstatus
        if (ec != 0)
            puts "Return value: #{ec}" if @verbose
            if (@fail_soft)
                return ec
            else
                raise "Execution returned non-zero exit code: " + ec.to_s
            end
        end
        return 0
    end

    def safeExec(cmd, args, no_stdout = false, detached = false)
        printCommand(cmd, args)
        if (not @dry_run)
            pid = fork
            if (pid.nil?)
                STDOUT.close() if (no_stdout)
                Kernel.exec(cmd, *args)
            else
                if (detached)
                    return Process.detach(pid) != nil ? 0 : 1
                else
                    ec = Process.waitpid2(pid,0)[1]
                    return handleExitCode(ec)
                end
            end
        end
        return 0
    end

    def printCommand(cmd, args)
        if (@verbose)
            puts((@dry_run ? '#' : '') + "#{cmd} #{args.join(' ')}"); 
            STDOUT.flush
        end
    end

    def execReadPipe(cmd, args, stdin = nil, &block)
        printCommand(cmd,args)
        rd, wr = IO.pipe
        pid = fork
        if pid
            wr.close
            block.call(rd)
            rd.close
            ec = Process.waitpid2(pid,0)[1]
            return handleExitCode(ec)
        else
            rd.close
            if (stdin != nil)
                STDIN.reopen(stdin)
            end
            STDOUT.reopen(wr)
            Kernel.exec cmd, *args
        end
    end

    def execBackTick(cmd, args)
        retval = ""
        execReadPipe(cmd, args) {
            |fd|
            data = nil
            while ((data = fd.read(5000)) != nil)
                retval += data
            end
        }
        return retval
    end

    def execWritePipe(cmd, args, &block)
        printCommand(cmd,args)
        rd, wr = IO.pipe
        pid = fork
        if pid
            rd.close
            block.call(wr)
            wr.close
            ec = Process.waitpid2(pid,0)[1]
            return handleExitCode(ec)
        else
            wr.close
            STDIN.reopen(rd)
            Kernel.exec cmd, *args
        end
    end

end

