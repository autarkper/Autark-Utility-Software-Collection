module AutarkFileUtils

    Separator_re = %r|/+|

    def self.make_relative(source, target)
        target_parts = target.split(Separator_re)
        source_parts = source.split(Separator_re)

        # remove empty first part, caused by leading "/"
        target_parts.shift
        source_parts.shift

        if (target_parts[0] != source_parts[0])
            return source
        end

        match = true
        rel_parts = []
        target_parts.each {
            |part|
            if (source_parts.empty?)
                rel_parts.unshift('..')
                next
            end

            source_part = source_parts.shift
            match = match && (source_part == part)
            if (not match)
                rel_parts.push(source_part)
                rel_parts.unshift('..')
            end
        }
        rel_parts.push(source_parts)
        rel_path = rel_parts.flatten.join('/')
        return rel_path
    end
end
