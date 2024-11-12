
//  ContentView.swift
//  iosApplication
//  Created by Amar Ganta on 10/11/24.

import SwiftUI
import SwiftData
import Foundation
import Combine
import PhotosUI
import Network

// MARK: - UserDefaults Extension for Offline Product Handling
extension UserDefaults {
    private static let offlineProductsKey = "OfflineProducts"
    
    // Save a product to UserDefaults if network is unavailable
    static func saveOfflineProduct(_ product: Product) {
        var offlineProducts = getOfflineProducts()
        offlineProducts.append(product)
        if let encodedData = try? JSONEncoder().encode(offlineProducts) {
            UserDefaults.standard.set(encodedData, forKey: offlineProductsKey)
        }
    }
    
    // Retrieve the list of offline products from UserDefaults
    static func getOfflineProducts() -> [Product] {
        guard let data = UserDefaults.standard.data(forKey: offlineProductsKey),
              let products = try? JSONDecoder().decode([Product].self, from: data) else {
            return []
        }
        return products
    }
    
    // Clear the stored offline products
    static func clearOfflineProducts() {
        UserDefaults.standard.removeObject(forKey: offlineProductsKey)
    }
}

// MARK: - Network Monitor for Detecting Network Connectivity
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied // Updates network connection status
            }
        }
        monitor.start(queue: queue) // Start monitoring network status
    }
}

// MARK: - Model for Product Data
struct Product: Identifiable, Codable {
    var id = UUID() // Unique identifier for each product
    var image: String?
    var price: Double
    var productName: String
    var productType: String
    var tax: Double
    var isFavorite: Bool = false // Whether the product is marked as favorite
    var isUserAdded: Bool = false // Track if the product is user-added
    
    enum CodingKeys: String, CodingKey {
        case image, price, tax
        case productName = "product_name"
        case productType = "product_type"
    }
}

// MARK: - Network Manager for Handling API Requests and Offline Product Sync
class NetworkManager: ObservableObject {
    @Published var products: [Product] = [] // List of products fetched from API
    @Published var isLoading = false // Indicator for loading state
    private var cancellables = Set<AnyCancellable>() // Set to store Combine cancellables
    
    private var networkMonitor = NetworkMonitor.shared // Shared network monitor
    
    init() {
        // Listen for changes in network connectivity status
        networkMonitor.$isConnected
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.submitOfflineProducts() // Submit offline products when network is available
                }
            }
            .store(in: &cancellables)
    }
    
    // Submit a product to the API if connected, otherwise save it offline
    func subbmitProductToAPI(_ product: Product, imageData: Data?, completion: @escaping (Bool) -> Void) {
        if !networkMonitor.isConnected {
            UserDefaults.saveOfflineProduct(product) // Save the product offline if no network
            completion(true) // Indicate that product was saved offline
            return
        }
        
        // Code for submitting product to the API (not provided here)
    }
    
    // Submit all offline products when network becomes available
    private func submitOfflineProducts() {
        let offlineProducts = UserDefaults.getOfflineProducts()
        
        // Iterate through offline products and attempt to submit them
        for product in offlineProducts {
            subbmitProductToAPI(product, imageData: nil) { success in
                if success {
                    UserDefaults.clearOfflineProducts() // Clear offline products after successful submission
                }
            }
        }
    }
    
    // Fetch products from the API
    func fetchProducts() {
        isLoading = true // Start loading products
        guard let url = URL(string: "https://app.getswipe.in/api/public/get") else { return }
        
        // Perform a network request to fetch products from the given URL
        URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: [Product].self, decoder: JSONDecoder())
            .replaceError(with: []) // If there's an error, return an empty list
            .receive(on: DispatchQueue.main) // Ensure UI updates happen on the main thread
            .sink { [weak self] in
                self?.products = $0 // Assign fetched products to the products list
                self?.isLoading = false // Stop loading state
            }
            .store(in: &cancellables)
    }
    
    // Add a product to the products list
    func addProduct(_ product: Product) {
        products.append(product)
    }
    
    // Toggle the favorite state of a product
    func toggleFavorite(for product: Product) {
        if let index = products.firstIndex(where: { $0.id == product.id }) {
            products[index].isFavorite.toggle()
        }
    }
    
    // Function to submit product to the API with optional image data
    func submitProductToAPI(_ product: Product, imageData: Data?, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://app.getswipe.in/api/public/add") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST" // Set HTTP method to POST
        
        // Set boundary for multipart/form-data request
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Construct form-data body with product details
        var body = Data()
        
        // Append product details to body as form-data
        body.append(convertFormField(named: "product_name", value: product.productName, using: boundary))
        body.append(convertFormField(named: "product_type", value: product.productType, using: boundary))
        body.append(convertFormField(named: "price", value: String(product.price), using: boundary))
        body.append(convertFormField(named: "tax", value: String(product.tax), using: boundary))
        
        // Append image data if available
        if let imageData = imageData {
            body.append(convertFileData(fieldName: "files[]",
                                        fileName: "product_image.jpg",
                                        mimeType: "image/jpeg",
                                        fileData: imageData,
                                        using: boundary))
        }
        
        // Close the multipart form data with boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Perform the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error submitting product: \(error)")
                    completion(false)
                    return
                }
                
                // Check response and handle success/failure
                if let data = data {
                    do {
                        if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let success = jsonResponse["success"] as? Bool, success == true {
                            print("Product submitted successfully.")
                            completion(true)
                        } else {
                            completion(false)
                        }
                    } catch {
                        print("Error parsing response: \(error)")
                        completion(false)
                    }
                }
            }
        }.resume()
    }
    
    // Helper function to create form field for multipart form-data
    private func convertFormField(named name: String, value: String, using boundary: String) -> Data {
        var fieldString = "--\(boundary)\r\n"
        fieldString += "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        fieldString += "\r\n"
        fieldString += "\(value)\r\n"
        return Data(fieldString.utf8)
    }
    
    // Helper function to create file data for multipart form-data
    private func convertFileData(fieldName: String,
                                 fileName: String,
                                 mimeType: String,
                                 fileData: Data,
                                 using boundary: String) -> Data {
        var fieldData = Data()
        fieldData.append("--\(boundary)\r\n".data(using: .utf8)!)
        fieldData.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        fieldData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        fieldData.append(fileData)
        fieldData.append("\r\n".data(using: .utf8)!)
        return fieldData
    }
}



// MARK: - Views
// ProductListView displays the list of products with filtering and category-based sections
struct ProductListView: View {
    @ObservedObject var networkManager: NetworkManager // Observable object that manages network data
    @State private var searchText = "" // State variable for search input text

    // Filter products based on search text
    var filteredProducts: [Product] {
        if searchText.isEmpty {
            return networkManager.products
        } else {
            return networkManager.products.filter { $0.productName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // Define a two-column grid layout
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all) // Set background color for the entire view
                
                VStack {
                    // Header with logo and title
                    HStack {
                        Spacer()
                        Image("best-product") // App logo
                            .resizable()
                            .frame(width: 50, height: 50) // Adjust the size of the logo
                        
                        Text("CatalogHub")
                            .font(Font.custom("Avenir-Heavy", size: 34))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    .padding(.bottom, 10)
                    
                    // Search bar for filtering products
                    SearchBar(text: $searchText)
                        .padding(.horizontal)

                    // Display loading indicator if products are being fetched
                    if networkManager.isLoading {
                        ProgressView("Loading Products...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                            .foregroundColor(.black)
                    } else {
                        // Display products in a grid layout
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                // User-Added Products Section
                                if !filteredProducts.filter({ $0.isUserAdded }).isEmpty {
                                    Section(header: Text("User-Added Products").foregroundColor(.blue).padding(.top, 10)) {
                                        ForEach(filteredProducts.filter { $0.isUserAdded }.indices, id: \.self) { index in
                                            let product = filteredProducts.filter { $0.isUserAdded }[index]
                                            ProductCardView(product: product, networkManager: networkManager, index: index)
                                                .padding(.vertical, 4)
                                        }
                                    }
                                }
                                
                                // Favorites Section
                                if !filteredProducts.filter({ $0.isFavorite }).isEmpty {
                                    Section(header: Text("Favorites").font(Font.custom("Avenir-Heavy", size: 14)).foregroundColor(.black).padding(.top, 6)) {
                                        ForEach(filteredProducts.filter { $0.isFavorite }.indices, id: \.self) { index in
                                            let product = filteredProducts.filter { $0.isFavorite }[index]
                                            ProductCardView(product: product, networkManager: networkManager, index: index)
                                                .padding(.vertical, 4)
                                        }
                                    }
                                }
                                
                                // All Products Section
                                Section(header: Text("All Products").font(Font.custom("Avenir-Heavy", size: 14)).foregroundColor(.black).padding(.top, 6)) {
                                    ForEach(filteredProducts.filter { !$0.isFavorite && !$0.isUserAdded }.indices, id: \.self) { index in
                                        let product = filteredProducts.filter { !$0.isFavorite && !$0.isUserAdded }[index]
                                        ProductCardView(product: product, networkManager: networkManager, index: index)
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .onAppear {
                    // Fetch products when the view appears
                    networkManager.fetchProducts()
                }
            }
        }
    }
}


// MARK: - Product Card View
// Displays an individual product in a card format
struct ProductCardView: View {
    var product: Product
    @ObservedObject var networkManager: NetworkManager
    var index: Int // Index for determining background color

    // Array of colors for different product categories
    let colors: [Color] = [
        Color.blue.opacity(0.1), // Electronics
        Color.pink.opacity(0.1), // Clothing
        Color.orange.opacity(0.1), // Home Goods
        Color.green.opacity(0.1), // Food
        Color.purple.opacity(0.1), // Books
        Color.yellow.opacity(0.1) // Miscellaneous
    ]

    // Get color based on the product index
    var cardBackgroundColor: Color {
        colors[index % colors.count]
    }

    var body: some View {
        VStack {
            // Display product image, if available
            if let imageUrl = product.image, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(12)
                } placeholder: {
                    Image(systemName: "photo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.gray)
                }
            } else {
                // Placeholder image when no product image is available
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(.gray)
            }
            
            // Product details
            VStack(alignment: .leading, spacing: 5) {
                Text(product.productName)
                    .font(.headline)
                    .foregroundColor(.black)
                
                Text("Type: \(product.productType)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("Tax: \(String(format: "%.2f", product.tax))%")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("₹\(String(format: "%.2f", product.price))")
                    .font(.headline)
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            // Favorite button to toggle product's favorite status
            Button(action: {
                networkManager.toggleFavorite(for: product)
            }) {
                Image(systemName: product.isFavorite ? "heart.fill" : "heart")
                    .foregroundColor(product.isFavorite ? .red : .gray)
                    .font(.system(size: 20))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(cardBackgroundColor) // Background color based on product index
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 4)
    }
}




// MARK: - Add Product View
struct AddProductView: View {
    @ObservedObject var networkManager: NetworkManager
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @State private var productName = ""  // State for product name input
    @State private var selectedProductType = ""  // State for selected product type
    @State private var price = ""  // State for product price input
    @State private var tax = ""  // State for product tax input
    @State private var selectedImageItem: PhotosPickerItem? = nil  // State for selected image item
    @State private var selectedImage: UIImage? = nil  // State for selected image
    @State private var alertType: AlertType? = nil  // State for showing alert messages

    // Array of product types for the picker
    let productTypes = ["Electronics", "Clothing", "Food", "Books", "Home Goods"]

    // Enum for different types of alerts (success or validation)
    enum AlertType: Identifiable {
        var id: String { UUID().uuidString }
        
        case success
        case validation(message: String)
    }

    var body: some View {
        // NavigationView provides a context for navigation-related UI elements
        NavigationView {
            VStack {
                // Scrollable view to allow scrolling if the content overflows
                ScrollView {
                    VStack(spacing: 20) {
                        // Section for product details
                        Section(header: Text("Product Details").font(.headline)) {
                            // TextField for entering the product name
                            TextField("Product Name", text: $productName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)

                            // Picker for selecting product type
                            Picker("Product Type", selection: $selectedProductType) {
                                Text("Select Type").tag("")  // Default empty option
                                ForEach(productTypes, id: \.self) { type in
                                    Text(type).tag(type)  // List all product types
                                }
                            }
                            .pickerStyle(MenuPickerStyle())  // Style of the picker as a menu
                            .padding(.horizontal)

                            // TextField for entering the product price
                            TextField("Price", text: $price)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)  // Numeric input for decimal values
                                .padding(.horizontal)

                            // TextField for entering the product tax percentage
                            TextField("Tax", text: $tax)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)  // Numeric input for decimal values
                                .padding(.horizontal)
                        }

                        // Section for selecting the product image
                        Section(header: Text("Product Image").font(.headline)) {
                            // PhotosPicker allows the user to select an image from their gallery
                            PhotosPicker(
                                selection: $selectedImageItem,  // Binds the selected image item
                                matching: .images,  // Filters to only show images
                                preferredItemEncoding: .automatic  // Automatically chooses item encoding
                            ) {
                                Text("Select Image")
                                    .foregroundColor(.purple)  // Purple color for the select button
                                    .padding(.horizontal)
                            }
                            // Load the selected image asynchronously
                            .task {
                                if let newItem = selectedImageItem {
                                    loadImage(from: newItem)
                                }
                            }

                            // Display the selected image (if available)
                            if let selectedImage = selectedImage {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))  // Rounded corners for the image
                            } else {
                                // If no image is selected, display a message
                                Text("No image selected")
                                    .foregroundColor(.gray)
                                    .padding(.horizontal)
                            }
                        }

                        // Button to add the product
                        Button(action: addProduct) {
                            Text("Add Product")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.purple)  // Purple background for the button
                                .cornerRadius(10)
                                .padding(.horizontal)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemGray6))  // Light gray background for the form
                    .cornerRadius(10)
                    .padding()
                }
            }
            .background(Color(UIColor.systemGray6))  // Set the overall background color
            .navigationBarTitleDisplayMode(.inline)  // Keeps title in the navigation bar
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Custom title for the navigation bar
                    Text("Add New Product")
                        .font(.custom("Avenir-Heavy", size: 26))  // Custom font for title
                        .foregroundColor(.black)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert(item: $alertType) { alert in
                // Display an alert based on the alert type
                switch alert {
                case .success:
                    return Alert(title: Text("Product Added"), message: Text("The product is added successfully!"), dismissButton: .default(Text("OK")))
                case .validation(let message):
                    return Alert(title: Text("Warning"), message: Text(message), dismissButton: .default(Text("OK")))
                }
            }
        }
    }
    
    // Function to add a new product
    func addProduct() {
        // Validate input fields
        guard !productName.isEmpty, !selectedProductType.isEmpty, let price = Double(price), let tax = Double(tax) else {
            alertType = .validation(message: "Please complete all fields correctly.")  // Show validation alert
            return
        }

        // Create a new product object
        let newProduct = Product(image: nil, price: price, productName: productName, productType: selectedProductType, tax: tax, isUserAdded: true)

        // Check if the product already exists in the product list
        if networkManager.products.contains(where: { $0.productName == newProduct.productName && $0.productType == newProduct.productType && $0.price == newProduct.price && $0.tax == newProduct.tax }) {
            alertType = .validation(message: "Product already exists.")  // Show validation alert
            return
        }

        // Convert the selected image to JPEG data (if available)
        let imageData = selectedImage?.jpegData(compressionQuality: 0.8)

        // Check if the user is offline and save the product offline
        if !networkMonitor.isConnected {
            UserDefaults.saveOfflineProduct(newProduct)  // Save product locally
            alertType = .validation(message: "You're offline. The product will be uploaded once online.")
            return
        }

        // Submit the new product to the API
        networkManager.submitProductToAPI(newProduct, imageData: imageData) { success in
            if success {
                networkManager.addProduct(newProduct)  // Add product to the network manager
                alertType = .success  // Show success alert
            } else {
                alertType = .validation(message: "Failed to add product. Please try again.")  // Show error alert
            }
        }
    }
    
    // Function to load the selected image from the PhotosPicker item
    func loadImage(from item: PhotosPickerItem) {
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                if let data = data, let image = UIImage(data: data) {
                    selectedImage = image  // Set the selected image
                } else {
                    print("Failed to convert data to UIImage")
                }
            case .failure(let error):
                print("Failed to load image data: \(error)")
            }
        }
    }
}



// MARK: - Search Bar
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")  // Search icon
                .foregroundColor(.gray)
            
            TextField("Search products...", text: $text)  // Search field
                .padding(8)
                .background(Color(.systemGray6))  // Background color for the text field
                .cornerRadius(8)
                .disableAutocorrection(true)
                .foregroundColor(.primary)
            
            // Clear button for the search field
            if !text.isEmpty {
                Button(action: {
                    text = ""  // Clear the search text
                }) {
                    Image(systemName: "xmark.circle.fill")  // Clear icon
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 4)
    }
}


// MARK: - Main ContentView
struct ContentView: View {
    @StateObject private var networkManager = NetworkManager()
    
    init() {
        // Set the appearance of the TabBar
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white  // Set background color for the TabBar
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance  // Set appearance for scrollable edges
        }
    }
    
    var body: some View {
        // TabView for displaying different views (ProductList and AddProduct)
        TabView {
            ProductListView(networkManager: networkManager)
                .tabItem {
                    Label("Products", systemImage: "square.grid.2x2")  // Products tab icon and label
                }
            
            AddProductView(networkManager: networkManager)
                .tabItem {
                    Label("Add Product", systemImage: "plus.rectangle.on.rectangle")  // Add Product tab icon and label
                }
                .padding(.top)
        }
        .accentColor(.purple)  // Set the accent color for the tabs
    }
}

#Preview {
    ContentView()
}

