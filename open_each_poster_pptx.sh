for i in *; do
    [ -d "$i" ] || continue
    file=$(ls "$i/File submissions/$i"*.pptx 2>/dev/null | head -n1)
    [ -n "$file" ] || continue
    echo "Opening $file"
    open "$file"
    read -p "Press Enter for next poster..."
done
