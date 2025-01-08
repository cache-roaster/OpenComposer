require "uri"

# Return true if the provided icon is in a valid URL format.
def valid_url?(icon)
  return false if icon.nil? || (!icon.start_with?("http://") && !icon.start_with?("https://"))
  
  uri = URI.parse(icon)
  return uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
rescue URI::InvalidURIError => e
  halt 500, e.message
end

helpers do
  # Create an HTML snippet for displaying a thumbnail image.
  # The image source can either be a URL, a bootstrap icon, a fontawesome icon or a local path.
  # If the icon is not provided. a placeholder image is used.
  def output_thumbnail(dirname, name, icon)
    is_bi_or_fa_icon = false # Bootstrap icon or Font Awesome icon
    icon_path = url + "no_image_square.jpg"

    if !icon.nil?
      if valid_url?(icon)
        icon_path = icon
      else
        icon_path = "#{@script_name}/apps/#{dirname}/#{icon}"
        icon_local_path = File.join(Dir.pwd, icon_path)
        file_exist = File.exist?(icon_local_path)
        if (icon.start_with?("bi-") || icon.start_with?("fa-")) && !file_exist
          is_bi_or_fa_icon = true
        end
      end
    end

    # Use the text-reset class to prevent color changes when using font awesome icons
    html = <<~HTML
      <div class="col text-center">
        <a href="#{@script_name}/#{dirname}" class="stretched-link position-relative text-reset">
HTML
    width = @conf['thumbnail_width']
    if is_bi_or_fa_icon
      html << "<i class=\"#{icon}\" style=\"font-size: #{width}px; width: #{width}px; height: 100px; line-height: 1;\"></i>"
    else
      html << "<img src=\"#{icon_path}\" class=\"img-thumbnail\" width=\"#{width}\" height=\"100\" alt=\"#{name}\">"
    end
    html << <<~HTML
        </a>
        <br>
        #{name}
      </div>
    HTML
  end
end
