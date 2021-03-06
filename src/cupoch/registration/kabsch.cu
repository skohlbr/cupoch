#include <thrust/reduce.h>
#include <thrust/inner_product.h>
#include <thrust/iterator/permutation_iterator.h>

#include <Eigen/Geometry>
#include <Eigen/SVD>

#include "cupoch/registration/kabsch.h"

using namespace cupoch;
using namespace cupoch::registration;

Eigen::Matrix4f_u cupoch::registration::Kabsch(
        const utility::device_vector<Eigen::Vector3f> &model,
        const utility::device_vector<Eigen::Vector3f> &target,
        const CorrespondenceSet &corres) {
    // Compute the center
    Eigen::Vector3f model_center = thrust::reduce(
            thrust::make_permutation_iterator(model.begin(),
                    thrust::make_transform_iterator(corres.begin(), extract_element_functor<int, 2, 0>())),
            thrust::make_permutation_iterator(model.begin(),
                    thrust::make_transform_iterator(corres.end(), extract_element_functor<int, 2, 0>())),
            Eigen::Vector3f(0.0, 0.0, 0.0), thrust::plus<Eigen::Vector3f>());
    Eigen::Vector3f target_center = thrust::reduce(
            thrust::make_permutation_iterator(target.begin(),
                    thrust::make_transform_iterator(corres.begin(), extract_element_functor<int, 2, 1>())),
            thrust::make_permutation_iterator(target.begin(),
                    thrust::make_transform_iterator(corres.end(), extract_element_functor<int, 2, 1>())),
            Eigen::Vector3f(0.0, 0.0, 0.0), thrust::plus<Eigen::Vector3f>());
    float divided_by = 1.0f / model.size();
    model_center *= divided_by;
    target_center *= divided_by;

    // Centralize them
    // Compute the H matrix
    const Eigen::Matrix3f init = Eigen::Matrix3f::Zero();
    Eigen::Matrix3f hh = thrust::inner_product(
            thrust::make_permutation_iterator(model.begin(),
                    thrust::make_transform_iterator(corres.begin(), extract_element_functor<int, 2, 0>())),
            thrust::make_permutation_iterator(model.begin(),
                    thrust::make_transform_iterator(corres.end(), extract_element_functor<int, 2, 0>())),
            thrust::make_permutation_iterator(target.begin(),
                    thrust::make_transform_iterator(corres.begin(), extract_element_functor<int, 2, 1>())),
            init, thrust::plus<Eigen::Matrix3f>(),
            [model_center, target_center] __device__ (const Eigen::Vector3f& lhs, const Eigen::Vector3f& rhs) {
                return (lhs - model_center) * (rhs - target_center).transpose();
            });

    // Do svd
    hh /= model.size();
    Eigen::JacobiSVD<Eigen::Matrix3f> svd(hh, Eigen::ComputeFullU | Eigen::ComputeFullV);
    Eigen::Matrix3f ss = Eigen::Matrix3f::Identity();
    ss(2, 2) = (svd.matrixU() * svd.matrixV()).determinant();
    Eigen::Matrix4f tr = Eigen::Matrix4f::Identity();
    tr.block<3, 3>(0, 0) = svd.matrixV() * ss * svd.matrixU().transpose();

    // The translation
    tr.block<3, 1>(0, 3) = target_center;
    tr.block<3, 1>(0, 3) -= tr.block<3, 3>(0, 0) * model_center;

    return tr;
}

Eigen::Matrix4f_u cupoch::registration::Kabsch(
        const utility::device_vector<Eigen::Vector3f> &model,
        const utility::device_vector<Eigen::Vector3f> &target) {
    CorrespondenceSet corres(model.size());
    thrust::tabulate(corres.begin(), corres.end(),
                     [] __device__ (size_t idx) {
                         return Eigen::Vector2i(idx, idx);
                     });
    return Kabsch(model, target, corres);
}