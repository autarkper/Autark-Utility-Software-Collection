module ExifToolUtils
    @@excludes = []
    %w(Orientation ExifImageHeight ExifImageWidth ResolutionUnit YResolution XResolution IFD0:Orientation IFD1:Orientation
        ColorSpace ComponentsConfiguration YCbCrPositioning SubjectArea GainControl Contrast Saturation Sharpness SceneCaptureType
        SceneType
        ).each {
        |tag|
        @@excludes.push("-#{tag}=")
    }

    def self.copyExif(syscommand, source, target)
        syscommand.safeExec("exiftool", ['-TagsFromFile', source,'-exif:all', @@excludes, '-overwrite_original', target].flatten, true)
    end
end

