package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
)

func main() {
	// Get the SAML response file path from command line argument or use default
	samlResponseFile := "/tmp/saml-response.txt"
	if len(os.Args) > 1 {
		samlResponseFile = os.Args[1]
	}
	
	ctx, cancel := context.WithCancel(context.Background())

	log.Printf("Starting SAML response listener at :35001")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case "POST":
			if err := r.ParseForm(); err != nil {
				fmt.Fprintf(w, "ParseForm() err: %v", err)
				return
			}
			SAMLResponse := r.FormValue("SAMLResponse")
			if len(SAMLResponse) == 0 {
				log.Printf("SAMLResponse field is empty or not exists")
				return
			}
			os.WriteFile(samlResponseFile, []byte(url.QueryEscape(SAMLResponse)), 0600)
			w.Header().Add("Content-Type", "text/html")
			fmt.Fprintf(w, "Got SAMLResponse field, it is now safe to close this window"+"<script>window.close()</script>")

			log.Printf("Received SAML response. Exiting...")
			cancel()
		default:
			fmt.Fprintf(w, "Error: POST method expected, %s recieved", r.Method)
		}
	})

	server := &http.Server{Addr: ":35001"}
	go func() {
		err := server.ListenAndServe()
		if err != http.ErrServerClosed {
			log.Println(err)
		}
	}()

	<-ctx.Done() // wait for the signal to gracefully shutdown the server

	err := server.Shutdown(context.Background())
	if err != nil {
		log.Println(err)
	}

	log.Println("done.")
}