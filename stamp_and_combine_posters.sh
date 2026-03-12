echo brew install imagemagick
echo brew install ghostscript

mkdir -p stamped

mkdir -p stamped

for f in */File\ submissions/*.pdf; do
  magick -density 600 "$f" \
    -gravity southeast \
    -font "/System/Library/Fonts/Supplemental/Arial.ttf" \
    -pointsize 32 \
    -fill black \
    -annotate +40+40 "$(basename "$f")" \
    "stamped/$(basename "$f")"
done


echo brew install pdftk-java
echo pdftk ./stamped/*.pdf cat output combined_posters.pdf

