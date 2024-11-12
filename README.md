# CatalogHub
An iOS application that allows users to manage products effectively. This project demonstrates skills in building functional and visually appealing iOS apps with features such as product listing, searching, adding, and favoriting. It uses modern Swift development practices and ensures offline functionality for seamless user experience.
## 📋 Project Overview

### Purpose
To build an iOS app with two primary screens:
1. **Product Listing Screen**: Display products fetched from an API with features like search, favoriting, and dynamic image handling.
2. **Add Product Screen**: Allow users to add new products with validation, image uploads, and offline syncing capabilities.

### Key Features
- **Product Listing Screen**:
  - Search for products.
  - Display a scrollable list of products.
  - Highlight favorited products at the top of the list.
  - Dynamic image loading with fallback to a default image.
  - Navigate to the Add Product screen.

- **Add Product Screen**:
  - Input fields for product name, price, tax, and type.
  - Optional image upload (JPEG/PNG, 1:1 aspect ratio).
  - Field validation for completeness and correct data formats.
  - Offline functionality: Syncs products when internet is restored.



## 🛠️ Technologies Used
- **Language**: Swift
- **Framework**: SwiftUI (for UI design)
- **Architecture**: MVVM (Model-View-ViewModel)
- **Version Control**: Git



## 🌐 API Endpoints

### Fetch Products
- **Method**: GET  
- **URL**: [https://app.getswipe.in/api/public/get](https://app.getswipe.in/api/public/get)  
- **Expected Response**:  
  ```json
  [
    {
      "image": "URL",
      "price": 1694.91,
      "product_name": "Sample Product",
      "product_type": "Product",
      "tax": 18.0
    }
  ]
Add Product
Method: POST
URL: https://app.getswipe.in/api/public/add
Parameters:
product_name (text)
product_type (text)
price (text)
tax (text)
files[] (file, optional for images)
Expected Response:
json
Copy code
{
  "message": "Product added Successfully!",
  "product_details": { ... },
  "product_id": 2657,
  "success": true
}
## 🚀 How to Run the Project
- Clone the Repository
- Open the project in Xcode.
- Set the deployment target to a compatible iOS version.
- Run the App:
Use a simulator or physical device to test the app.

## Offline Functionality
- Products created offline are stored locally.
- They are automatically synced with the server once the internet is available.

## Additional Notes
- ### Best Practices:
  -  Followed MVVM architecture for clean code separation.
  - Validations implemented for better user experience.


## Future Enhancements
- Localization: Add support for multiple languages.
- Animations: Make the UI more interactive.
- Caching: Cache API data for faster loading.

## Author
Developed by Amar Harish Ganta as part of an iOS development to demonstrate skills in Swift development, UI design, and API integration.

## License
This project is licensed under the MIT License.
