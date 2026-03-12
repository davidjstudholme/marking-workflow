for i in *; do
    pdf=$(ls "$i/File submissions/$i"*.pdf | head -n1)
    echo "Opening $pdf"
    open "$pdf"
    read -p "Press Enter for next poster..."
done


